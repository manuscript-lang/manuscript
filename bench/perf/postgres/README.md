# Postgres client throughput

The `packages/postgres` client against Go's `pgx` and Rust's `tokio-postgres`: 4 connections, each running 20000 sequential point lookups (`select id, name, score from items where id = $1`, one prepared statement, one round trip per lookup) on a 10000-row table. Each program opens its own connections, so connect and login are in the time. Every program prints the checksum of the scores it read, and the driver fails on a mismatch.

```sh
sh packages/postgres/tests/start-postgres.sh   # prints the PG* variables to export
MS=./target/release/ms ms run bench/tools/postgres_bench.ms -- 9
```

The driver copies `packages/postgres/src` into `ms/pg` (a project keeps its imports inside its root), builds the three programs into `.build/`, creates the table, and runs them in rotating order, reporting medians. `WORKERS` and `QUERIES` change the shape.

Designs match: one connection per worker, one prepared statement, strictly sequential lookups. Differences that are not the language: pgx and tokio-postgres fetch results in the binary format, while the Manuscript client uses text; the server runs on the same machine and shares its 4 cores with the clients; `tokio-postgres` spawns a task per connection on a multi-thread runtime.

## 2026-11-15, Linux amd64, 4 cores (Xeon 2.10 GHz), PostgreSQL 16 on localhost, revision 3dde763e

| Program | Median of 9 | Lookups per second |
| --- | --- | --- |
| Manuscript | 0.687 s | 116,393 |
| Go pgx v5.13.0 | 0.884 s | 90,486 |
| Rust tokio-postgres 0.7.18 | 1.523 s | 52,520 |

A first run of 5 samples gave 1.082 s, 0.860 s and 1.424 s: Manuscript moved by 1.6x between runs on this shared VM, so treat the order of Manuscript and pgx as unsettled. The slow tokio-postgres result held in both runs and has not been investigated; the likely cause is the runtime sharing the 4 cores with the server, not the library. Instruction counts (`valgrind --tool=callgrind`) have not been taken.
