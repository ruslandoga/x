defmodule X.Imports do
  @moduledoc "Imports data into `imported_*` tables"

  @spec import_archive(DBConnection.conn(), pos_integer, Path.t(), Keyword.t()) ::
          %{(table :: String.t()) => num_rows :: non_neg_integer}
  def import_archive(conn, site_id, zip_path, opts \\ []) do
    # TODO zip bombs?
    # https://fly.io/phoenix-files/can-phoenix-safely-use-the-zip-module/#conclusion
    {:ok, files} = :zip.unzip(to_charlist(zip_path), cwd: to_charlist(System.tmp_dir!()))

    try do
      timeout = Keyword.get(opts, :timeout, :timer.seconds(15))
      tmp_suffix = "_staging_#{site_id}_import"

      {[meta], files} =
        Enum.split_with(files, fn file -> Path.basename(file) == "metadata.json" end)

      %{"version" => "0", "files" => meta} = meta |> File.read!() |> Jason.decode!()

      Enum.each(files, fn file ->
        %{"table" => table} = Map.fetch!(meta, Path.basename(file))
        Ch.query!(conn, "CREATE TEMPORARY TABLE #{table <> tmp_suffix} AS #{table}")
      end)

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
                  "INSERT INTO #{table <> tmp_suffix} SELECT {site_id:UInt64}, * FROM ",
                  input(table),
                  " FORMAT ",
                  format,
                  ?\n
                ],
                %{"site_id" => site_id}
                # TODO settings
                # https://clickhouse.com/blog/supercharge-your-clickhouse-data-loads-part2
              )

            Enum.into(File.stream!(file), stream)
          end,
          timeout: timeout
        )
      end)

      Map.new(files, fn file ->
        %{"table" => table} = Map.fetch!(meta, Path.basename(file))
        staging_table = table <> tmp_suffix

        %Ch.Result{num_rows: num_rows} =
          Ch.query!(conn, "INSERT INTO #{table} SELECT * FROM #{staging_table}")

        # TODO maybe this? it's more acid (moving the same partition twice would fail)
        # conn
        # |> Ch.query!(
        #   "SELECT partition FROM system.parts WHERE table = {table:String} GROUP BY partition ORDER BY partition",
        #   %{"table" => staging_table}
        # )
        # |> Enum.each(fn [partition] ->
        #   Ch.query!(
        #     conn,
        #     "ALTER TABLE #{staging_table} MOVE PARTITION #{partition} TO TABLE #{table}"
        #   )
        # end)

        {table, num_rows}
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
