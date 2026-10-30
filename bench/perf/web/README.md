# Web server benchmark

The same HTTP server written with Manuscript's standard library ([`ms/`](ms)), Go's `net/http` ([`go/`](go)) and, when `cargo` is installed, hyper ([`rust/`](rust), two tokio workers; no `/io`), driven by one keep-alive load generator ([`load/`](load)). It measures the runtime's I/O path: the reactor, parking, timers, and, through `/io`, file and DNS calls that the kernel cannot poll.

| Endpoint | Work |
| --- | --- |
| `/health` | a 3-byte body |
| `/user/<id>` | a small JSON object |
| `/top?n=10` | 10 selection passes over 1,000 scores, as a JSON array |
| `/io?<slot>` | resolve `localhost`, write 1 MiB to the connection's own file, read it back |

```sh
cargo build --release --locked -p ms-cli
sh bench/perf/web/run.sh 5
```

`run.sh [seconds]` serves Manuscript from `MS_THREADS` workers (default 2, matching `SERVER_CPUS`; the main thread accepts and deals connections round robin), so every server gets the same two cores. It needs Go and, for the system-call rows, `strace`. On a machine with at least four CPUs it pins the server to `SERVER_CPUS` (default `0,1`) and the load generator to `LOAD_CPUS` (default `2,3`). It runs each server in turn and prints one line per measurement:

- each endpoint twice, 64 connections: requests per second, p50, p99, failed requests;
- `io`, then `health-during-io`: 32 connections on `/health` while 32 others run `/io`;
- threads and resident memory after the load;
- system calls in 5 idle seconds, and per `/health` request under load;
- resident memory with 10,000 idle keep-alive connections open, and `/health` throughput beside them.

`sh bench/perf/web/fetch.sh [seconds]` measures the client side the same way: `fetch` against Go's `net/http` client on small and 8 MiB bodies, plus one 8 MiB body sent chunked and one gzip-compressed (`/chunked/big`, `/gzip/text`).

Compare numbers only within one run on one machine. Shared virtual machines vary by 10 to 15% between runs; run twice and report both. [`results.md`](results.md) records the latest numbers.
