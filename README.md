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
I'm reusing the data from Plausible PostgreSQL and ClickHouse containers:
```console
$ docker ps
CONTAINER ID   IMAGE                                          COMMAND                  CREATED          STATUS              PORTS                                        NAMES
6a8a9c9b9ff3   minio/minio                                    "/usr/bin/docker-ent…"   2 seconds ago    Up 1 second         0.0.0.0:9000-9001->9000-9001/tcp             export_s3
684a4a155d1a   clickhouse/clickhouse-server:23.3.7.5-alpine   "/entrypoint.sh"         12 seconds ago   Up 11 seconds       9000/tcp, 0.0.0.0:8123->8123/tcp, 9009/tcp   crazy_fermat
228e2aa476a8   postgres:15-alpine                             "docker-entrypoint.s…"   3 months ago     Up About a minute   0.0.0.0:5432->5432/tcp
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

TO READ:
- [text](https://clickhouse.com/docs/knowledgebase/finding_expensive_queries_by_memory_usage)
- [text](https://stackoverflow.com/questions/67784231/why-does-clickhouse-need-so-much-memory-for-a-simple-query)
- [text](https://stackoverflow.com/questions/65316905/clickhouse-dbexception-memory-limit-for-query-exceeded)
- [text](https://www.youtube.com/watch?v=lnbWFjfZxZ4)
- [text](https://www.youtube.com/watch?v=2ygBtU4gKFc)
- [text](https://medium.com/@johnpaulhayes/aws-s3-javascript-sdk-multi-file-upload-in-the-browser-1cae0019bb34)
- [text](https://medium.com/@bryzgaloff/how-to-implement-lambda-architecture-using-clickhouse-9109e78c718b)
- [text](https://github.com/ClickHouse/examples/blob/8b7b3114ba35d95aff7386f7adf0fb57e304f09a/large_data_loads/src/worker.py#L606)
- [text](https://github.com/ClickHouse/examples/blob/main/large_data_loads/examples/pypi/README.md#example-for-resiliently-loading-a-large-data-set)
- [text](https://clickhouse.com/blog/clickhouse-release-23-05#parquet-reading-even-faster-michael-kolupaev)
- [text](https://clickhouse.com/blog/apache-parquet-clickhouse-local-querying-writing-internals-row-groups#compression)
- [text](https://github.com/ClickHouse/examples/tree/main/large_data_loads#clickload)
- [text](https://clickhouse.com/blog/clickhouse-release-23-08#reading-files-faster-michael-kolupaevpavel-kruglov)
- [text](https://clickhouse.com/cloud/clickpipes)
- [text](https://github.com/ClickHouse/examples/tree/main/large_data_loads)
- [text](https://aws.amazon.com/blogs/compute/uploading-large-objects-to-amazon-s3-using-multipart-upload-and-transfer-acceleration/)
- [text](https://github.com/aws-samples/amazon-s3-multipart-upload-transfer-acceleration)
- [text](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)
- [text](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)
- [text](https://stackoverflow.com/questions/66603679/how-can-i-safely-upload-a-large-file-from-the-browser-to-a-bucket-on-amazon-s3)
- [text](https://aws.amazon.com/blogs/compute/uploading-to-amazon-s3-directly-from-a-web-or-mobile-application/)
- [text](https://www.linkedin.com/pulse/uploading-large-files-aws-s3-lightning-fast-speed-parallel-asif)
- [text](https://windowsreport.com/upload-large-files-to-s3-from-browser/)
- [text](https://aameer.github.io/articles/secure-fast-uploads-for-large-files-directly-from-browser-to-s3/)
- [text](https://lemire.me/blog/2021/06/30/compressing-json-gzip-vs-zstd/)
- [text](https://nickb.dev/blog/there-and-back-again-with-zstd-zips/)
