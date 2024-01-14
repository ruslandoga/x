defmodule X.Imports.S3 do
  use Oban.Worker

  @impl true
  def perform(job) do
    %Oban.Job{args: %{"s3_key" => s3_key, "site_id" => site_id}} = job

    {:ok, conn} =
      X.Ch.Repo.config()
      |> Keyword.replace!(:pool_size, 1)
      |> Keyword.update(:settings, [session_id: "import_#{site_id}"], fn settings ->
        Keyword.put(settings, :session_id, "import_#{site_id}")
      end)
      |> Ch.start_link()

    X.Imports.import_s3_archive(conn, site_id, s3_key)

    X.Mailer.deliver!(
      Swoosh.Email.new(
        from: "x@localhost",
        to: "#{site_id}@localhost",
        subject: "IMPORT SUCCESS",
        text_body: "IMPORT COMPLETE"
      )
    )

    :ok
  end
end
