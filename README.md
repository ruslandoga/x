csv export/import demo

```console
$ docker run --rm -d -p 5432:5432 -e POSTGRES_PASSWORD="postgres" --name export_db postgres:15-alpine
043f0cd44951d81c04dd9acf832b6ca6ffd92f933e20a46feb895f1aaf88145e
$ docker run --rm -d -p 8123:8123 --ulimit nofile=262144:262144 --name export_ch clickhouse/clickhouse-server:23.3.7.5-alpine
a4004255c5aa3ce66335e1a4cde7b0b606056da657d154e1a47bc03910a1acfb
$ docker run --rm -d -p 9000:9000 -p 9001:9001 --name export_s3 minio/minio server /data --console-address ":9001"
1d0f20bbfa65bfd692078f5e84ebf8c53e70801f355be4557cd772ec01493d15
$ docker exec export_s3 mc alias set local http://localhost:9000 minioadmin minioadmin
Added `local` successfully.
$ docker exec export_s3 mc mb local/imports
Bucket created successfully `local/imports`.
$ mix ecto.setup
The database for X.Repo has already been created
The database for X.Ch.Repo has been created
17:55:44.816 [info] Migrations already up
17:55:44.829 [info] Migrations already up
```
