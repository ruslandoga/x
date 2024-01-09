defmodule X.ExportsTest do
  use X.DataCase

  describe "export_archive/5" do
    setup do
      {:ok, ch} = X.Ch.Repo.config() |> Keyword.replace!(:pool_size, 1) |> Ch.start_link()
      {:ok, ch: ch}
    end

    test "success", %{ch: ch} do
      queries = X.Exports.export_queries(_site_id = 1)
      queries = Enum.map(queries, fn {name, query} -> {"#{name}.csv", query} end)

      zip_path =
        Path.join(
          System.tmp_dir!(),
          "export-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}.zip"
        )

      :ok = File.touch!(zip_path)
      on_exit(fn -> File.rm!(zip_path) end)

      {:ok, fd} =
        X.Exports.export_archive(
          ch,
          queries,
          File.open!(zip_path, [:raw, :binary, :append]),
          fn data, fd -> {:ok = :file.write(fd, data), fd} end,
          format: "CSVWithNames",
          # headers: [{"accept-encoding", "zstd"}],
          # settings: [enable_http_compression: 1],
          timeout: :infinity
        )

      :ok = File.close(fd)

      on_exit(fn -> X.truncate_imported_tables() end)
      :ok = X.Imports.import_archive(ch, _site_id = 11, zip_path)

      expected_counts = %{
        "imported_browsers" => 3604,
        "imported_devices" => 2884,
        "imported_entry_pages" => 55943,
        "imported_exit_pages" => 55804,
        "imported_locations" => 5046,
        "imported_operating_systems" => 2163,
        "imported_pages" => 56520,
        "imported_sources" => 721,
        "imported_visitors" => 721
      }

      for {table, count} <- expected_counts do
        assert Ch.query!(
                 ch,
                 "select count(*) from {table:Identifier} where site_id = {site_id:UInt64}",
                 %{"table" => table, "site_id" => 11}
               ).rows ==
                 [[count]]
      end
    end

    test "raises on Ch.Error", %{ch: ch} do
      assert_raise Ch.Error,
                   ~r/Code: 62. DB::Exception: Syntax error: failed at position 8/,
                   fn ->
                     X.Exports.export_archive(
                       ch,
                       _queries = [{"some_fail.csv", "select ", [{"a", "b"}]}],
                       _acc = nil,
                       fn _data, acc -> {:ok, acc} end,
                       format: "CSVWithNames"
                     )
                   end
    end
  end
end
