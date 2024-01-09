defmodule X.Exports do
  @moduledoc "Exports data for events and sessions."

  import Ecto.Query

  # TODO do in one pass over both tables?

  @doc """
  Builds Ecto queries for a website.
  """
  @spec export_queries(pos_integer) :: %{atom => Ecto.Query.t()}
  def export_queries(site_id) do
    %{
      visitors: export_visitors_q(site_id),
      sources: export_sources_q(site_id),
      # TODO
      pages: export_pages_q(site_id),
      entry_pages: export_entry_pages_q(site_id),
      exit_pages: export_exit_pages_q(site_id),
      locations: export_locations_q(site_id),
      devices: export_devices_q(site_id),
      browsers: export_browsers_q(site_id),
      operating_systems: export_operating_systems_q(site_id)
    }
  end

  defmacrop date(timestamp) do
    quote do
      selected_as(fragment("toDate(?)", unquote(timestamp)), :date)
    end
  end

  defmacrop visit_duration(t) do
    quote do
      selected_as(
        fragment(
          "toUInt32(round(?))",
          sum(unquote(t).sign * unquote(t).duration) / sum(unquote(t).sign)
        ),
        :visit_duration
      )
    end
  end

  defmacrop visitors(t) do
    quote do
      selected_as(fragment("uniq(?)", unquote(t).user_id), :visitors)
    end
  end

  defmacrop visits(t) do
    quote do
      selected_as(sum(unquote(t).sign), :visits)
    end
  end

  defmacrop bounces(t) do
    quote do
      selected_as(sum(unquote(t).sign * unquote(t).is_bounce), :bounces)
    end
  end

  @spec export_visitors_q(pos_integer) :: Ecto.Query.t()
  def export_visitors_q(site_id) do
    visitors_sessions_q =
      from s in "sessions_v2",
        hints: ["SAMPLE", "2000000"],
        where: s.site_id == ^site_id,
        group_by: selected_as(:date),
        select: %{
          date: date(s.start),
          bounces: bounces(s),
          visits: visits(s),
          visit_duration: visit_duration(s)
        }

    visitors_events_q =
      from e in "events_v2",
        hints: ["SAMPLE", "2000000"],
        where: e.site_id == ^site_id,
        group_by: selected_as(:date),
        select: %{
          date: date(e.timestamp),
          visitors: visitors(e),
          pageviews: selected_as(fragment("countIf(?='pageview')", e.name), :pageviews)
        }

    visitors_q =
      "e"
      |> with_cte("e", as: ^visitors_events_q)
      |> with_cte("s", as: ^visitors_sessions_q)

    from e in visitors_q,
      full_join: s in "s",
      on: e.date == s.date,
      order_by: selected_as(:date),
      select: [
        selected_as(fragment("greatest(?,?)", s.date, e.date), :date),
        e.visitors,
        e.pageviews,
        s.bounces,
        s.visits,
        s.visit_duration
      ]
  end

  @spec export_sources_q(pos_integer) :: Ecto.Query.t()
  def export_sources_q(site_id) do
    from s in "sessions_v2",
      hints: ["SAMPLE", "2000000"],
      where: s.site_id == ^site_id,
      group_by: [
        selected_as(:date),
        s.utm_source,
        s.utm_campaign,
        s.utm_medium,
        s.utm_content,
        s.utm_term
      ],
      order_by: selected_as(:date),
      select: [
        date(s.start),
        selected_as(s.utm_source, :source),
        s.utm_campaign,
        s.utm_content,
        s.utm_term,
        visitors(s),
        visits(s),
        visit_duration(s),
        bounces(s)
      ]
  end

  @spec export_pages_q(pos_integer) :: Ecto.Query.t()
  def export_pages_q(site_id) do
    window_q =
      from e in "events_v2",
        hints: ["SAMPLE", "2000000"],
        where: e.site_id == ^site_id,
        select: %{
          timestamp: e.timestamp,
          next_timestamp:
            over(fragment("leadInFrame(?)", e.timestamp),
              partition_by: e.session_id,
              order_by: e.timestamp,
              frame: fragment("ROWS BETWEEN CURRENT ROW AND 1 FOLLOWING")
            ),
          pathname: e.pathname,
          hostname: e.hostname,
          name: e.name,
          user_id: e.user_id
        }

    from e in subquery(window_q),
      group_by: [selected_as(:date), e.pathname],
      order_by: selected_as(:date),
      select: [
        date(e.timestamp),
        selected_as(e.pathname, :path),
        selected_as(fragment("any(?)", e.hostname), :hostname),
        selected_as(
          fragment("sum(greatest(?,0))", e.next_timestamp - e.timestamp),
          :time_on_page
        ),
        # TODO
        selected_as(fragment("countIf(?='pageview' and ?=0)", e.name, e.next_timestamp), :exits),
        selected_as(fragment("countIf(?='pageview')", e.name), :pageviews),
        visitors(e)
      ]
  end

  @spec export_entry_pages_q(pos_integer) :: Ecto.Query.t()
  def export_entry_pages_q(site_id) do
    from s in "sessions_v2",
      hints: ["SAMPLE", "2000000"],
      where: s.site_id == ^site_id,
      group_by: [selected_as(:date), s.entry_page],
      order_by: selected_as(:date),
      select: [
        date(s.start),
        s.entry_page,
        visitors(s),
        selected_as(sum(s.sign), :entrances),
        visit_duration(s),
        bounces(s)
      ]
  end

  @spec export_exit_pages_q(pos_integer) :: Ecto.Query.t()
  def export_exit_pages_q(site_id) do
    from s in "sessions_v2",
      hints: ["SAMPLE", "2000000"],
      where: s.site_id == ^site_id,
      group_by: [selected_as(:date), s.exit_page],
      order_by: selected_as(:date),
      select: [
        date(s.start),
        s.exit_page,
        visitors(s),
        selected_as(sum(s.sign), :exits)
      ]
  end

  @spec export_locations_q(pos_integer) :: Ecto.Query.t()
  def export_locations_q(site_id) do
    from s in "sessions_v2",
      hints: ["SAMPLE", "2000000"],
      where: s.site_id == ^site_id,
      group_by: [selected_as(:date), s.country_code, selected_as(:region), s.city_geoname_id],
      order_by: selected_as(:date),
      select: [
        date(s.start),
        selected_as(s.country_code, :country),
        # TODO avoid "AK-", "-US", "-"
        selected_as(
          fragment("concatWithSeparator('-',?,?)", s.subdivision1_code, s.subdivision2_code),
          :region
        ),
        selected_as(s.city_geoname_id, :city),
        visitors(s),
        visits(s),
        visit_duration(s),
        bounces(s)
      ]
  end

  @spec export_devices_q(pos_integer) :: Ecto.Query.t()
  def export_devices_q(site_id) do
    from s in "sessions_v2",
      hints: ["SAMPLE", "2000000"],
      where: s.site_id == ^site_id,
      group_by: [selected_as(:date), s.screen_size],
      order_by: selected_as(:date),
      select: [
        date(s.start),
        selected_as(s.screen_size, :device),
        visitors(s),
        visits(s),
        visit_duration(s),
        bounces(s)
      ]
  end

  @spec export_browsers_q(pos_integer) :: Ecto.Query.t()
  def export_browsers_q(site_id) do
    from s in "sessions_v2",
      hints: ["SAMPLE", "2000000"],
      where: s.site_id == ^site_id,
      group_by: [selected_as(:date), s.browser],
      order_by: selected_as(:date),
      select: [
        date(s.start),
        s.browser,
        visitors(s),
        visits(s),
        visit_duration(s),
        bounces(s)
      ]
  end

  @spec export_operating_systems_q(pos_integer) :: Ecto.Query.t()
  def export_operating_systems_q(site_id) do
    from s in "sessions_v2",
      hints: ["SAMPLE", "2000000"],
      where: s.site_id == ^site_id,
      group_by: [selected_as(:date), s.operating_system],
      order_by: selected_as(:date),
      select: [
        date(s.start),
        s.operating_system,
        visitors(s),
        visits(s),
        visit_duration(s),
        bounces(s)
      ]
  end

  # TODO cleanup, return Stream.t
  @spec export_archive(
          DBConnection.conn(),
          queries :: [{name, sql :: iodata, params :: [term]} | {name, query :: Ecto.Query.t()}],
          on_data_acc,
          on_data :: (iodata, on_data_acc -> {:ok, on_data_acc}),
          opts :: Keyword.t()
        ) :: {:ok, on_data_acc}
        when name: String.t(), on_data_acc: term
  def export_archive(conn, queries, on_data_acc, on_data, opts \\ []) do
    {metadata_entry, encoded} = X.Zip.start_entry("metadata.json")
    {:ok, on_data_acc} = on_data.(encoded, on_data_acc)

    raw_queries =
      Enum.map(queries, fn query ->
        case query do
          {name, query} ->
            {sql, params} = X.Ch.Repo.to_sql(:all, query)

            # TODO do it in ecto_ch
            params =
              params
              |> Enum.with_index()
              |> Enum.map(fn {value, idx} -> {"$#{idx}", value} end)

            {name, sql, params}

          {_name, _sql, _params} = ready ->
            ready
        end
      end)

    format = Keyword.fetch!(opts, :format)

    metadata =
      Jason.encode_to_iodata!(%{
        "version" => "0",
        "files" =>
          Map.new(raw_queries, fn {name, _sql, _params} ->
            [table | _extensions] = String.split(name, ".")
            table = "imported_#{table}"
            {name, %{"format" => format, "table" => table}}
          end)
      })

    {:ok, on_data_acc} = on_data.(metadata, on_data_acc)
    metadata_entry = X.Zip.grow_entry(metadata_entry, metadata)
    {metadata_entry, encoded} = X.Zip.end_entry(metadata_entry)
    {:ok, on_data_acc} = on_data.(encoded, on_data_acc)

    ch_opts = Keyword.take(opts, [:settings, :format, :headers])
    zip_opts = Keyword.take(opts, [:compression])

    {entries, on_data_acc} =
      DBConnection.run(
        conn,
        fn conn ->
          Enum.reduce(raw_queries, {[], on_data_acc}, fn {name, sql, params},
                                                         {entries, on_data_acc} ->
            {entry, encoded} = X.Zip.start_entry(name, zip_opts)
            {:ok, on_data_acc} = on_data.(encoded, on_data_acc)

            {entry, on_data_acc} =
              conn
              |> Ch.stream(sql, params, ch_opts)
              |> Enum.reduce({entry, on_data_acc}, fn result, {entry, on_data_acc} = acc ->
                case result do
                  %Ch.Result{data: []} ->
                    acc

                  %Ch.Result{data: data} ->
                    {:ok, on_data_acc} = on_data.(data, on_data_acc)
                    {X.Zip.grow_entry(entry, data), on_data_acc}
                end
              end)

            {entry, encoded} = X.Zip.end_entry(entry)
            {:ok, on_data_acc} = on_data.(encoded, on_data_acc)
            {[entry | entries], on_data_acc}
          end)
        end,
        timeout: Keyword.get(opts, :timeout, :infinity)
      )

    {:ok, _on_data_acc} =
      on_data.(
        X.Zip.encode_central_directory([metadata_entry | :lists.reverse(entries)]),
        on_data_acc
      )
  end
end
