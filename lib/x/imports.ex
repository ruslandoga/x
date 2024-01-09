defmodule X.Imports do
  @moduledoc "Imports data into `imported_*` tables"

  @spec import_archive(DBConnection.conn(), pos_integer, Path.t(), Keyword.t()) :: :ok
  def import_archive(conn, site_id, zip_path, opts \\ []) do
    # TODO zip bombs?
    # https://fly.io/phoenix-files/can-phoenix-safely-use-the-zip-module/#conclusion
    {:ok, files} = :zip.unzip(to_charlist(zip_path), cwd: to_charlist(System.tmp_dir!()))
    timeout = Keyword.get(opts, :timeout, :timer.seconds(15))

    # TODO temp tables

    try do
      {[meta], files} =
        Enum.split_with(files, fn file -> Path.basename(file) == "metadata.json" end)

      %{"version" => "0", "files" => meta} = meta |> File.read!() |> Jason.decode!()

      Enum.each(files, fn file ->
        %{"format" => format, "table" => table} = Map.fetch!(meta, Path.basename(file))
        ensure_supported_format(format)

        DBConnection.run(
          conn,
          fn conn ->
            # TODO zstd? Native?
            stream =
              Ch.stream(
                conn,
                [
                  "INSERT INTO {table:Identifier} SELECT {site_id:UInt64}, * FROM ",
                  input(table),
                  " FORMAT ",
                  format,
                  ?\n
                ],
                %{"table" => table, "site_id" => site_id}
                # TODO settings
                # https://clickhouse.com/blog/supercharge-your-clickhouse-data-loads-part2
              )

            Enum.into(File.stream!(file), stream)
          end,
          timeout: timeout
        )
      end)
    after
      :ok = Enum.each(files, &File.rm!/1)
    end
  end

  inputs = %{
    "imported_browsers" =>
      "date Date, browser String, visitors UInt64, visits UInt64, visit_duration UInt64, bounces UInt32",
    "imported_devices" =>
      "date Date, device String, visitors UInt64, visits UInt64, visit_duration UInt64, bounces UInt32",
    "imported_entry_pages" =>
      "date Date, entry_page String, visitors UInt64, entrances UInt64, visit_duration UInt64, bounces UInt64",
    "imported_exit_pages" => "date Date, exit_page String, visitors UInt64, exits UInt64",
    "imported_locations" =>
      "date Date, country String, region String, city UInt64, visitors UInt64, visits UInt64, visit_duration UInt64, bounces UInt32",
    "imported_operating_systems" =>
      "date Date, operating_system String, visitors UInt64, visits UInt64, visit_duration UInt64, bounces UInt32",
    "imported_pages" =>
      "date Date, hostname String, page String, visitors UInt64, pageviews UInt64, exits UInt64, time_on_page UInt64",
    "imported_sources" =>
      "date Date, source String, utm_medium String, utm_campaign String, utm_content String, utm_term String, visitors UInt64, visits UInt64, visit_duration UInt64, bounces UInt32",
    "imported_visitors" =>
      "date Date, visitors UInt64, pageviews UInt64, bounces UInt64, visits UInt64, visit_duration UInt64"
  }

  for {table, schema} <- inputs do
    defp input(unquote(table)), do: unquote("input('" <> schema <> "')")
  end

  for format <- ["Native", "CSVWithNames"] do
    defp ensure_supported_format(unquote(format)), do: :ok
  end
end
