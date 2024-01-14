defmodule X.S3ExportsTest do
  use X.DataCase

  describe "export_s3_archive/4" do
    setup do
      {:ok, ch} =
        X.Ch.Repo.config()
        |> Keyword.replace!(:pool_size, 1)
        |> Keyword.put(:settings, session_id: "s3_export_import_test_#{inspect(self())}")
        |> Ch.start_link()

      {:ok, ch: ch}
    end

    test "e2e (almost)", %{ch: ch} do
      queries = X.Exports.export_queries(_site_id = 1)
      queries = Enum.map(queries, fn {name, query} -> {"#{name}.csv", query} end)

      assert %URI{} =
               url =
               X.Exports.export_s3_archive(
                 ch,
                 queries,
                 _s3_key = "exports/site-1-just-now.plausible",
                 format: "CSVWithNames"
               )

      # as if the user is downloading it
      download_req = Finch.build(:get, URI.to_string(url))
      %Finch.Response{status: 200, body: exported_zip} = Finch.request!(download_req, X.Finch)

      # now the user uploads it via a form or a signed url
      s3_key = "upload_for_#{_site_id = 123}"

      Oban.insert!(
        X.S3.Cleaner.new(
          %{"url" => "http://localhost:9000/imports", "path" => s3_key},
          schedule_in: 86400
        )
      )

      upload_url =
        X.S3.signed_url(
          X.S3.config(
            method: :put,
            url: "http://localhost:9000/imports",
            path: s3_key,
            query: %{"X-Amz-Expires" => 86400}
          )
        )

      upload_req = Finch.build(:put, URI.to_string(upload_url), _headers = [], exported_zip)
      %Finch.Response{status: 200} = Finch.request!(upload_req, X.Finch)

      # and now we import it from S3 into ClickHouse

      zip_path =
        Path.join(
          System.tmp_dir!(),
          "import_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}.zip"
        )

      :ok = File.touch!(zip_path)
      on_exit(fn -> File.rm!(zip_path) end)
      fd = File.open!(zip_path, [:raw, :binary, :append])

      {uri, headers, body} =
        X.S3.build(X.S3.config(method: :get, url: "http://localhost:9000/imports", path: s3_key))

      req = Finch.build(:get, uri, headers, body)

      {:ok, %Finch.Response{status: 200}} =
        Finch.stream(req, X.Finch, fd, fn
          {:status, status}, fd ->
            if status == 200 do
              %Finch.Response{status: status, body: fd}
            else
              %Finch.Response{status: status, body: ""}
            end

          {:headers, headers}, resp ->
            %Finch.Response{resp | headers: headers}

          {:data, data}, resp ->
            case resp do
              %Finch.Response{status: 200, body: fd} ->
                :ok = :file.write(fd, data)
                resp

              %Finch.Response{body: body} when is_binary(body) ->
                %Finch.Response{resp | body: body <> data}
            end
        end)

      :ok = File.close(fd)

      assert %{
               "imported_browsers" => 3604,
               "imported_devices" => 2884,
               "imported_entry_pages" => 55943,
               "imported_exit_pages" => 55804,
               "imported_locations" => 5046,
               "imported_operating_systems" => 2163,
               "imported_pages" => 56520,
               "imported_sources" => 721,
               "imported_visitors" => 721
             } = X.Imports.import_archive(ch, _site_id = 123, zip_path)
    end
  end
end
