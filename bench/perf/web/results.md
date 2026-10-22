# Web server results

`sh bench/perf/web/run.sh 5` on a shared 4-CPU Linux VM, server on 2 CPUs, load on the other 2, Go 1.24.7 (`CGO_ENABLED=0`). Ranges cover both rounds of a run. Compare numbers only within one run: this host varies by 10 to 15% between runs.

| Measurement | Manuscript | Go |
| --- | ---: | ---: |
| `/health` req/s | 75.7k–81.9k | 54.8k–55.2k |
| `/user/42` req/s | 70.2k–75.3k | 52.1k–54.5k |
| `/top?n=10` req/s | 20.2k–20.4k | 23.6k–26.2k |
| `/health` p99 | 2.9–4.3 ms | 5.6–5.8 ms |
| `/io` req/s | 253–279 | 624–690 |
| `/health` req/s during `/io` | 773 | 2,538 |
| `/health` p99 during `/io` | 137 ms | 69 ms |
| Threads | 2 | 67 |
| Resident memory after load | 9.7 MB | 15 MB |
| System calls in 5 idle seconds | 0 | 1 |
| System calls per `/health` request | 2.07 | 2.73 |
| Resident memory, 10,000 idle connections | 31 MB | 197 MB |
| `/health` req/s beside 10,000 idle connections | 38.9k | 56.8k |

Where Manuscript is behind: file and DNS calls block the runtime thread, so `/io` and everything beside it wait on the disk, and `/health` slows beside many idle connections.

## History

| Change | `/health` req/s | System calls per request | Idle system calls in 5 s |
| --- | ---: | ---: | ---: |
| Baseline (`b69b5b65`; Go 52k–61k in the same run) | 38.8k–51.0k | 8.4 | 392–487 |
| Sockets registered once, reactor parks until real work | 75.7k–81.9k | 2.07 | 0 |
