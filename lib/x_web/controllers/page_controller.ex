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
        ch("export_#{@site_id}"),
        queries,
        conn,
        fn data, conn -> {:ok, _conn} = chunk(conn, data) end,
        format: "CSVWithNames"
      )

    conn
  end

  def s3_export(conn, _params) do
    Oban.insert!(X.Exports.S3.new(%{"site_id" => @site_id}))

    conn
    |> put_flash(:info, "EXPORT SCHEDULED")
    |> redirect(to: ~p"/")
  end

  def import(conn, %{"file" => %Plug.Upload{path: zip_path}}) do
    X.Imports.import_archive(ch("import_#{@site_id}"), @site_id, zip_path)

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

  defp ch(session_id) do
    {:ok, conn} =
      X.Ch.Repo.config()
      |> Keyword.replace!(:pool_size, 1)
      |> Keyword.update(:settings, [session_id: session_id], fn settings ->
        Keyword.put(settings, :session_id, session_id)
      end)
      |> Ch.start_link()

    conn
  end
end
