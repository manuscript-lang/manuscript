# postgres-service

A small HTTP service that counts visits in PostgreSQL. It depends on the
[ms-pg](https://github.com/manuscript-lang/ms-pg) package, pinned to a commit in `ms.toml` and `ms.lock`.

```sh
ms install                      # downloads the package; a locked build needs nothing else
PGPASSWORD=secret ms run      # needs a server; PGHOST, PGPORT, PGUSER and PGDATABASE also apply
curl http://127.0.0.1:8080/hello
```

Every request inserts a row and answers with the number of rows. A nightly job
(`.github/workflows/packages.yml`) fetches the package over https and builds and runs this service
against a real server on Linux, macOS and Windows.
