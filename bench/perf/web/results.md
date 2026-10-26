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

## 2026-10-25

`sh bench/perf/web/run.sh 5` on main at `6003f16b`, shared 4-CPU Linux VM, server on 2 CPUs, load on the other 2, Go 1.24.7. Ranges cover both rounds. Whole-file reads and writes already run on the blocking pool on Unix (`ms-std-fs/src/ops.rs`), which the first table above predates; this run records the effect.

| Measurement | Manuscript | Go |
| --- | ---: | ---: |
| `/health` req/s | 81.5k–92.4k | 61.4k–62.4k |
| `/user/42` req/s | 80.0k–85.4k | 57.1k–59.6k |
| `/top?n=10` req/s | 20.4k–22.4k | 26.3k–27.9k |
| `/health` p99 | 2.5 ms | 5.2–5.3 ms |
| `/io` req/s | 490–546 | 707–728 |
| `/health` req/s during `/io` | 24.0k | 2.0k |
| `/health` p99 during `/io` | 12.6 ms | 97 ms |
| Threads | 6 | 68 |
| Resident memory after load | 70 MB | 15 MB |
| System calls in 5 idle seconds | 2 | 72 |
| System calls per `/health` request | 2.08 | 2.65 |
| Resident memory, 10,000 idle connections | 93 MB | 197 MB |
| `/health` req/s beside 10,000 idle connections | 75.2k | 63.9k |

`/health` beside `/io` improved from 773 to 24.0k req/s and its p99 from 137 ms to 12.6 ms. Resident memory after load rose from 9.7 MB to 70 MB (the `/io` payloads and pool threads); not investigated. Windows is measured by CI only: the whole-file offload now compiles there too, but this suite has not run on it.

## 2026-10-25, one task per request

`/health`, `/user/42` and `/top?n=10`, 64 connections, 4 s, server on CPUs 0 and 1, load on 2 and 3, shared 4-CPU Linux VM (±10% between runs). Runs of main (`7439d30d`) and this change alternated, three rounds each. Each request now runs as a task of the server's scope instead of inline on the reactor task (`proposals/http-server-request-tasks.md`).

| Build | `/health` req/s | `/user/42` req/s | `/top?n=10` req/s |
| --- | ---: | ---: | ---: |
| main, inline handlers | 102k–115k | 100k–113k | 23k–25k |
| task per request, stack pool 512 | 95k–111k | 85k–106k | 23k–24k |
| task per request, stack pool 32 (spike) | 32k–33k | 32k–33k | 15k–17k |

The pool of 32 stacks overflows on each reactor batch (up to 64 requests spawn before any runs), so every request paid `mmap`, `mprotect` and two `munmap` calls. With 512 the cost left is about 7% on the shortest handlers (`/health` median 107k against 114k).

## 2026-10-26, fetch client

`sh bench/perf/web/fetch.sh 2`: Manuscript's `fetch` (one `Fetcher`, N tasks) and Go's `net/http` client against one Go file server on CPUs 0-1, clients on CPUs 2-3, shared 4-CPU Linux VM (+/-10% between runs). The Manuscript runtime uses one thread, Go's client two cores.

| Body, connections | Go req/s | Manuscript req/s |
| --- | ---: | ---: |
| 3 bytes, 1 | 4.2k | 6.6k |
| 3 bytes, 8 | 24.7k | 32.6k |
| 3 bytes, 64 | 30.0k | 38.0k |
| 8 MiB, 1 | 147 | 117 |
| 8 MiB, 8 | 221 | 90 |

Before this change an 8 MiB fetch ran at 40-81 req/s on one connection (seven memory-copy passes per body byte; now three). Callgrind over 20 fetches of 8 MiB: 1.18G to 0.52G instructions. `/io` (whole-file read and write) went from 676 to 756 req/s, with `/health` beside it from 26k to 40k req/s and its p99 from 11 to 5.8 ms: reads per request 40 to 5, writes 19 to 4. A 30-route router served 41k-46k requests per second before it stopped cloning its routes on each request, and 80k-83k after.
