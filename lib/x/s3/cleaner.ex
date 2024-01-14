defmodule X.S3.Cleaner do
  require Logger
  use Oban.Worker

  @impl true
  def perform(job) do
    %Oban.Job{args: %{"url" => url, "path" => path}} = job

    {uri, headers, body} =
      X.S3.build(X.S3.config(url: url, method: :delete, path: path))

    req = Finch.build(:delete, uri, headers, body)
    %Finch.Response{status: 204} = Finch.request!(req, X.Finch)

    Logger.debug("deleted #{inspect(url: url, path: path)} from S3")

    :ok
  end
end
