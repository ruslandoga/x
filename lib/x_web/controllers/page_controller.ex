defmodule XWeb.PageController do
  use XWeb, :controller

  @site_id 1

  def home(conn, _params) do
    render(conn, :home)
  end

  def export(conn, _params) do
    queries =
      @site_id
      |> X.Exports.export_queries()
      |> Enum.map(fn {name, query} -> {"#{name}.csv", query} end)

    conn =
      conn
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("content-disposition", ~s|attachment; filename="export.plausible"|)
      |> send_chunked(200)

    {:ok, conn} =
      X.Exports.export_archive(
        ch(),
        queries,
        conn,
        fn data, conn -> {:ok, _conn} = chunk(conn, data) end,
        format: "CSVWithNames"
        # format: "Naitve",
        # settings: [enable_http_compression: 1],
        # headers: [{"accept-encoding", "zstd"}],
        # compression: _as_if_no_compression = 0x0
      )

    conn
  end

  def import(conn, %{"files" => files}) do
    [%Plug.Upload{path: zip_path}] = files
    :ok = X.Imports.import_archive(ch(), @site_id, zip_path)

    conn
    |> put_flash(:info, "IMPORT SUCCESS")
    |> redirect(to: ~p"/")
  end

  defp ch do
    {:ok, conn} =
      X.Ch.Repo.config()
      |> Keyword.put(:pool_size, 1)
      |> Ch.start_link()

    conn
  end
end
