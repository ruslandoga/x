defmodule XWeb.ImportLive do
  use XWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      allow_upload(socket, :import,
        accept: ~w[.zip],
        auto_upload: true,
        max_entries: 1,
        # 5GB
        max_file_size: 5_000_000_000,
        external: &presign_upload/2,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen w-full" phx-drop-target={@uploads.import.ref}>
      <h2 class="text-lg p-4 flex items-center">
        Choose file
        <form
          class="ml-2 h-full flex items-center"
          action="#"
          method="post"
          phx-change="validate-upload-form"
          phx-submit="submit-upload-form"
        >
          <label class="flex items-center">
            <div class="bg-zinc-200 dark:bg-zinc-700 rounded p-1 hover:bg-zinc-300 dark:hover:bg-zinc-600 transition cursor-pointer">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="24"
                height="24"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                class="w-4 h-4"
              >
                <line x1="12" y1="5" x2="12" y2="19"></line>
                <line x1="5" y1="12" x2="19" y2="12"></line>
              </svg>
            </div>
            <span class="ml-2 text-sm text-zinc-600 dark:text-zinc-500">
              (or drag-and-drop anywhere)
            </span>
            <.live_file_input upload={@uploads.import} class="hidden" />
          </label>
        </form>
      </h2>

      <div class="flex flex-wrap">
        <%= for entry <- @uploads.import.entries do %>
          <div class="flex items-center w-full md:w-1/2 lg:w-1/3 p-3 bg-yellow-100 dark:bg-blue-900 transition">
            <div class="ml-4">
              <p class="font-semibold mb-2"><%= entry.client_name %></p>
              <p class="text-sm text-zinc-700 dark:text-zinc-300">progress: <%= entry.progress %>%</p>

              <%= for err <- upload_errors(@uploads.import, entry) do %>
                <p class="text-sm text-red-300 dark:text-zinc-300"><%= error_to_string(err) %></p>
              <% end %>

              <button
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="mt-2 leading-6 px-2 rounded bg-red-200 dark:bg-red-800 text-red-700 dark:text-red-300 hover:bg-red-300 dark:hover:bg-red-500 transition"
              >
                cancel
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate-upload-form", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("submit-upload-form", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :import, ref)}
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:too_many_files), do: "You have selected too many files"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp presign_upload(entry, socket) do
    url = "http://localhost:9000/imports"
    key = "upload_for_#{_site_id = 123}"

    Oban.insert!(X.S3.Cleaner.new(%{"url" => url, "path" => key}, schedule_in: 86400))

    url =
      X.S3.signed_url(
        X.S3.config(method: :put, url: url, path: key, query: %{"X-Amz-Expires" => 360})
      )

    {:ok, %{uploader: "S3", key: key, url: URI.to_string(url)}, socket}
  end

  defp handle_progress(:import, entry, socket) do
    if entry.done? do
      consume_uploaded_entry(socket, entry, fn _meta -> {:ok, nil} end)

      Oban.insert!(
        X.Imports.S3.new(%{"site_id" => 123, "s3_key" => "upload_for_#{_site_id = 123}"})
      )
    end

    {:noreply, socket}
  end
end
