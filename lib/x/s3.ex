defmodule X.S3 do
  @moduledoc "S3 API request builder"

  # TODO hide access_key_id and secret_access_key from inspect / logs

  @type option ::
          {:access_key_id, String.t()}
          | {:secret_access_key, String.t()}
          | {:url, URI.t() | :uri_string.uri_string()}
          | {:host, String.t()}
          | {:region, String.t()}
          | {:method, Finch.Request.method()}
          | {:path, String.t()}
          | {:query, Enumerable.t()}
          | {:headers, Mint.Types.headers()}
          | {:body, Finch.Request.body()}
          | {:utc_now, DateTime.t()}

  @spec config([option]) :: [option]
  def config(options) do
    Keyword.merge(Application.fetch_env!(:x, __MODULE__), options)
  end

  @spec build([option]) :: {URI.t(), Mint.Types.headers(), Finch.Request.body()}
  def build(options) do
    access_key_id = Keyword.fetch!(options, :access_key_id)
    secret_access_key = Keyword.fetch!(options, :secret_access_key)

    url =
      case Keyword.fetch!(options, :url) do
        url when is_binary(url) -> %{} = :uri_string.parse(url)
        %URI{} = uri -> Map.from_struct(uri)
        %{} = parsed -> parsed
      end

    host = Keyword.get(options, :host)
    path = Keyword.get(options, :path) || "/"
    query = Keyword.get(options, :query) || %{}
    region = Keyword.fetch!(options, :region)
    method = Keyword.fetch!(options, :method)
    headers = Keyword.get(options, :headers) || []
    body = Keyword.get(options, :body) || []

    # hidden options
    service = Keyword.get(options, :service, "s3")
    utc_now = Keyword.get(options, :utc_now) || DateTime.utc_now()

    amz_content_sha256 =
      case body do
        # https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
        {:stream, _stream} -> "STREAMING-AWS4-HMAC-SHA256-PAYLOAD"
        _ -> hex_sha256(body)
      end

    amz_date = Calendar.strftime(utc_now, "%Y%m%dT%H%M%SZ")

    headers =
      Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)
      |> put_header("host", host || url.host)
      |> put_header("x-amz-content-sha256", amz_content_sha256)
      |> put_header("x-amz-date", amz_date)
      |> Enum.sort_by(fn {k, _} -> k end)

    # TODO method() to ensure only valid atoms are allowed
    method = String.upcase(to_string(method))

    url_query = if q = url[:query], do: URI.decode_query(q), else: %{}

    query =
      Map.merge(url_query, query)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> URI.encode_query()

    path =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&:uri_string.quote/1)
      |> Enum.join("/")

    path =
      case Path.join(url[:path] || "/", path) do
        "/" <> _ = path -> path
        _ -> "/" <> path
      end

    amz_short_date = String.slice(amz_date, 0, 8)

    scope = IO.iodata_to_binary([amz_short_date, ?/, region, ?/, service, ?/, "aws4_request"])

    signed_headers =
      headers
      |> Enum.map(fn {k, _} -> k end)
      |> Enum.intersperse(?;)
      |> IO.iodata_to_binary()

    canonical_request = [
      method,
      ?\n,
      path,
      ?\n,
      query,
      ?\n,
      Enum.map(headers, fn {k, v} -> [k, ?:, v, ?\n] end),
      ?\n,
      signed_headers,
      ?\n,
      amz_content_sha256
    ]

    string_to_sign = [
      "AWS4-HMAC-SHA256\n",
      amz_date,
      ?\n,
      scope,
      ?\n,
      hex_sha256(canonical_request)
    ]

    signing_key =
      ["AWS4" | secret_access_key]
      |> hmac_sha256(amz_short_date)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    signature = hex_hmac_sha256(signing_key, string_to_sign)

    authorization = """
    AWS4-HMAC-SHA256 Credential=#{access_key_id}/#{scope},\
    SignedHeaders=#{signed_headers},\
    Signature=#{signature}\
    """

    headers = [{"authorization", authorization} | headers]

    body =
      with {:stream, stream} <- body do
        string_to_sign_prefix = [
          "AWS4-HMAC-SHA256-PAYLOAD",
          ?\n,
          amz_date,
          ?\n,
          scope,
          ?\n
        ]

        acc = %{
          prefix: IO.iodata_to_binary(string_to_sign_prefix),
          key: signing_key,
          signature: signature
        }

        {:stream, Stream.transform(stream, acc, &streaming_chunk/2)}
      end

    url = Map.merge(url, %{query: query, path: path})
    {struct!(URI, url), headers, body}
  end

  # https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html#sigv4-chunked-body-definition
  @spec streaming_chunk(iodata, acc) :: {[iodata], acc}
        when acc: %{prefix: binary, key: binary, signature: String.t()}
  defp streaming_chunk(chunk, acc) do
    %{
      prefix: string_to_sign_prefix,
      key: signing_key,
      signature: prev_signature
    } = acc

    string_to_sign = [
      string_to_sign_prefix,
      prev_signature,
      # hex_sha256("") =
      "\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n",
      hex_sha256(chunk)
    ]

    signature = hex_hmac_sha256(signing_key, string_to_sign)

    signed_chunk = [
      chunk |> IO.iodata_length() |> Integer.to_string(16),
      ";chunk-signature=",
      signature,
      "\r\n",
      chunk,
      "\r\n"
    ]

    {[signed_chunk], %{acc | signature: signature}}
  end

  @spec signature([option]) :: String.t()
  def signature(options) do
    secret_access_key = Keyword.fetch!(options, :secret_access_key)
    body = Keyword.fetch!(options, :body)
    region = Keyword.fetch!(options, :region)
    service = Keyword.get(options, :service, "s3")
    utc_now = Keyword.get(options, :utc_now) || DateTime.utc_now()
    amz_short_date = Calendar.strftime(utc_now, "%Y%m%d")

    signing_key =
      ["AWS4" | secret_access_key]
      |> hmac_sha256(amz_short_date)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    hex_hmac_sha256(signing_key, body)
  end

  @spec signed_url([option]) :: URI.t()
  def signed_url(options) do
    access_key_id = Keyword.fetch!(options, :access_key_id)
    secret_access_key = Keyword.fetch!(options, :secret_access_key)

    url =
      case Keyword.fetch!(options, :url) do
        url when is_binary(url) -> %{} = :uri_string.parse(url)
        %URI{} = uri -> Map.from_struct(uri)
        %{} = parsed -> parsed
      end

    host = Keyword.get(options, :host)
    path = Keyword.get(options, :path) || "/"
    query = Keyword.get(options, :query) || %{}
    region = Keyword.fetch!(options, :region)
    method = Keyword.fetch!(options, :method)
    headers = Keyword.get(options, :headers) || []

    # hidden options
    service = Keyword.get(options, :service, "s3")
    utc_now = Keyword.get(options, :utc_now) || DateTime.utc_now()

    # TODO method() to ensure only valid atoms are allowed
    method = String.upcase(to_string(method))

    amz_date = Calendar.strftime(utc_now, "%Y%m%dT%H%M%SZ")
    amz_short_date = String.slice(amz_date, 0, 8)
    scope = IO.iodata_to_binary([amz_short_date, ?/, region, ?/, service, ?/, "aws4_request"])

    headers =
      Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)
      |> put_header("host", host || url.host)
      |> Enum.sort_by(fn {k, _} -> k end)

    path =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&:uri_string.quote/1)
      |> Enum.join("/")

    path =
      case Path.join(url[:path] || "/", path) do
        "/" <> _ = path -> path
        _ -> "/" <> path
      end

    signed_headers =
      headers
      |> Enum.map(fn {k, _} -> k end)
      |> Enum.intersperse(?;)
      |> IO.iodata_to_binary()

    url_query = if q = url[:query], do: URI.decode_query(q), else: %{}
    query = Map.merge(url_query, query)

    query =
      Map.merge(
        %{
          "X-Amz-Algorithm" => "AWS4-HMAC-SHA256",
          "X-Amz-Credential" => "#{access_key_id}/#{scope}",
          "X-Amz-Date" => amz_date,
          "X-Amz-SignedHeaders" => signed_headers
        },
        query
      )

    query =
      query
      |> Enum.sort_by(fn {k, _} -> k end)
      |> URI.encode_query()

    canonical_request =
      [
        method,
        ?\n,
        path,
        ?\n,
        query,
        ?\n,
        Enum.map(headers, fn {k, v} -> [k, ?:, v, ?\n] end),
        ?\n,
        signed_headers,
        ?\n,
        "UNSIGNED-PAYLOAD"
      ]

    string_to_sign =
      [
        "AWS4-HMAC-SHA256\n",
        amz_date,
        ?\n,
        scope,
        ?\n,
        hex_sha256(canonical_request)
      ]

    signing_key =
      ["AWS4" | secret_access_key]
      |> hmac_sha256(amz_short_date)
      |> hmac_sha256(region)
      |> hmac_sha256(service)
      |> hmac_sha256("aws4_request")

    signature = hex_hmac_sha256(signing_key, string_to_sign)
    query = query <> "&X-Amz-Signature=" <> signature
    url = Map.merge(url, %{query: query, path: path})
    struct!(URI, url)
  end

  @compile inline: [put_header: 3]
  defp put_header(headers, key, value), do: [{key, value} | List.keydelete(headers, key, 1)]
  @compile inline: [hex: 1]
  defp hex(value), do: Base.encode16(value, case: :lower)
  @compile inline: [sha256: 1]
  defp sha256(value), do: :crypto.hash(:sha256, value)
  @compile inline: [hmac_sha256: 2]
  defp hmac_sha256(secret, value), do: :crypto.mac(:hmac, :sha256, secret, value)
  @compile inline: [hex_sha256: 1]
  defp hex_sha256(value), do: hex(sha256(value))
  @compile inline: [hex_hmac_sha256: 2]
  defp hex_hmac_sha256(secret, value), do: hex(hmac_sha256(secret, value))
end
