defmodule X.Exports.S3 do
  require Logger
  use Oban.Worker

  @impl true
  def perform(job) do
    %Oban.Job{args: %{"site_id" => site_id}} = job
    s3_key = "export_#{site_id}.plausible"
    queries = X.Exports.export_queries(site_id)

    {:ok, conn} = X.Ch.Repo.config() |> Keyword.replace!(:pool_size, 1) |> Ch.start_link()
    Logger.debug("uploaded export to #{s3_key}")
    download_url = X.Exports.export_s3_archive(conn, queries, s3_key, format: "CSVWithNames")
    Logger.debug("download it from #{download_url}")

    X.Mailer.deliver!(
      Swoosh.Email.new(
        from: "x@localhost",
        to: "#{site_id}@localhost",
        subject: "EXPORT SUCCESS",
        text_body: """
        download it from #{download_url}! hurry up! you have 24 hours!"
        """,
        html_body: """
        download it from <a href="#{download_url}">here</a>! hurry up! you have 24 hours!
        """
      )
    )

    :ok
  end
end
