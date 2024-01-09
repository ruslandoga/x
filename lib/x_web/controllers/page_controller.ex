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
      |> Enum.map(fn {name, query} -> {Atom.to_string(name), query} end)

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
      )

    conn
  end

  def import(conn, %{"file" => file}) do
    %Plug.Upload{path: zip_path} = file
    X.Imports.import_archive(ch(), @site_id, zip_path)

    conn
    |> put_flash(:info, "IMPORT SUCCESS")
    |> redirect(to: ~p"/")
  catch
    class, reason ->
      conn
      |> put_flash(:error, "IMPORT FAILED")
      |> redirect(to: ~p"/")

      :erlang.raise(class, reason, __STACKTRACE__)
  end

  defp ch do
    {:ok, conn} =
      X.Ch.Repo.config()
      |> Keyword.put(:pool_size, 1)
      |> Ch.start_link()

    conn
  end
end
