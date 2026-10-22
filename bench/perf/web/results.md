# Web server results

Two runs of `sh bench/perf/web/run.sh 5`; a range covers every round of both runs. Shared 4-CPU Linux VM, server on 2 CPUs, load on the other 2. Manuscript at `b69b5b65`, Go 1.24.7 (`CGO_ENABLED=0`).

| Measurement | Manuscript | Go |
| --- | ---: | ---: |
| `/health` req/s | 38.8k–51.0k | 52.2k–60.9k |
| `/user/42` req/s | 39.0k–47.8k | 55.3k–59.0k |
| `/top?n=10` req/s | 13.5k–16.3k | 23.8k–25.2k |
| `/health` p99 | 2.4–3.1 ms | 5.0–6.1 ms |
| `/io` req/s | 235–258 | 707–740 |
| `/health` req/s during `/io` | 448–534 | 2,472–2,624 |
| `/health` p99 during `/io` | 86–93 ms | 70–74 ms |
| Threads | 2 | 67–68 |
| Resident memory after load | 5.6–5.7 MB | 21–23 MB |
| System calls in 5 idle seconds | 392–487 | 127–158 |
| System calls per `/health` request | 8.4 | 2.7 |
| Resident memory, 10,000 idle connections | 29.5 MB | 197–201 MB |
| `/health` req/s beside 10,000 idle connections | 23.5k–26.7k | 53.8k–57.5k |

Where Manuscript is behind: file and DNS calls block the runtime thread, so `/io` and everything beside it wait on the disk; the server re-polls every 2 ms while idle; each request makes about 8 system calls; and readiness is re-registered per wait, which slows `/health` beside many idle connections.
