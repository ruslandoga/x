Plausible export/import demo

```console
$ docker run --rm -d -p 9000:9000 -p 9001:9001 --name export_s3 minio/minio server /data --console-address ":9001"
1d0f20bbfa65bfd692078f5e84ebf8c53e70801f355be4557cd772ec01493d15
$ docker exec export_s3 mc alias set local http://localhost:9000 minioadmin minioadmin
Added `local` successfully.
$ docker exec export_s3 mc mb local/imports
Bucket created successfully `local/imports`.
$ docker exec export_s3 mc mb local/exports
Bucket created successfully `local/exports`.
```

ClickHouse setup:

```sql
SELECT site_id, round(avg(events)) AS avg_events_per_day
FROM
(
    SELECT site_id, count(*) AS events
    FROM sessions_v2
    GROUP BY site_id, toDate(timestamp)
)
GROUP BY site_id

-- ┌─site_id─┬─avg_events_per_day─┐
-- │       2 │              15396 │
-- │       5 │              13343 │
-- │       1 │                279 │
-- └─────────┴────────────────────┘

SELECT table, formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk
FROM system.parts
WHERE (database = 'plausible_events_db') AND active
GROUP BY table

-- ┌─table─────────────┬─bytes_on_disk─┐
-- │ sessions_v2       │ 958.27 MiB    │
-- │ events_v2         │ 750.84 MiB    │
-- └───────────────────┴───────────────┘

SELECT table, formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed_bytes
FROM system.parts
WHERE (database = 'plausible_events_db') AND active
GROUP BY table

-- ┌─table─────────────┬─uncompressed_bytes─┐
-- │ sessions_v2       │ 15.18 GiB          │
-- │ events_v2         │ 17.18 GiB          │
-- └───────────────────┴────────────────────┘

SELECT site_id, count(*)
FROM events_v2
GROUP BY site_id

-- ┌─site_id─┬──count()─┐
-- │       2 │ 22048579 │
-- │       5 │ 19057389 │
-- │       1 │   215194 │
-- └─────────┴──────────┘
```
