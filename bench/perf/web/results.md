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

## 2026-10-26, large-block reuse and inline file calls

`sh bench/perf/web/run.sh 3` before and after this change, shared 4-CPU Linux VM (±10% between runs). Zeroed large buffers (`vec![0; n]`) bypassed the runtime's block cache and faulted in fresh pages on every file read, blocking-pool jobs mapped a new block for every large result, and a single-task program still sent each file call through the pool.

| Measurement | before | after |
| --- | ---: | ---: |
| `/io` req/s | 863–944 | 1,232–1,265 |
| `/health` req/s during `/io` | 46.4k | 75.5k |
| Resident memory after load | 70.9 MB | 54.5 MB |
| `/health` req/s | 122.5k–123.7k | 108.5k–109.7k |

`/health` is within the run-to-run noise of this host; Go measured 105k–106k in the first run.

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

## 2026-10-26, fetch bodies received in place

`ResponseBody.read_all()` receives a fixed-length HTTP/1 body straight into the result buffer, and `fetch` uses it. `sh bench/perf/web/fetch.sh` style run, 8 MiB body, client on CPUs 2-3, three rounds on the shared VM (+/-10%):

| Connections | Go req/s | Manuscript before | Manuscript after |
| --- | ---: | ---: | ---: |
| 1 | 158-207 | 120-136 | 138-146 |
| 8 | 255-365 | 104-126 | 150-155 |

User CPU for 3 s at 8 connections: 1.47 s before, 0.12 s after (the rest is kernel receive and page faults). The Manuscript client still runs on one core, Go's on two.

## 2026-10-26, server on several cores

`server <port> <dir> <threads>` starts that many workers, each running `serve` with `HttpServerOptions(shared: True)` on one shared listener. Server on CPUs 0-1, 64 keep-alive connections from CPUs 2-3, 4 s per row, shared 4-CPU Linux VM (+/-10% between runs); two runs each.

| Server | `/top?n=10` req/s | `/health` req/s |
| --- | ---: | ---: |
| Go `net/http` | 34.4k, 37.5k | 85.1k, 84.6k |
| Manuscript, 1 thread | 26.3k, 25.1k | 118.3k, 105.7k |
| Manuscript, 2 workers | 58.1k, 56.9k | 140.7k, 136.1k |
| Manuscript, 4 workers (2 CPUs) | 59.1k, 61.4k | 150.7k, 139.9k |

A first run of this table had 2 workers at 38.6k/39.1k on `/top` and 65-72k on `/health`, below one thread: Rust code in a worker allocated through musl's `malloc`, which has one process-wide lock, and a `futex` trace showed the two workers handing that lock back and forth. Workers now allocate small Rust blocks from a process-wide heap that is never unmapped, with per-thread free lists (`worker_heap` in `ms-rt/src/alloc.rs`).

## 2026-10-26, fetch on several cores

`fetch.sh` gained a row that spreads the 8 connections over 2 worker threads (`ms/fetch <url> 8 <secs> 2`), one `Fetcher` task group per worker. Same machine and pinning as above (clients on CPUs 2-3), 3 s, two runs.

| 8 MiB body, 8 connections | req/s |
| --- | ---: |
| Go `net/http` | 424, 437 |
| Manuscript, tasks on one thread | 165, 151 |
| Manuscript, 2 worker threads | 371, 374 |

Worker threads needed the large-block reuse in `ms-rt/alloc.rs`: before it, one worker fetched 70-84 req/s against 190-198 on the main thread, because each body buffer was mapped and faulted in again.

## 2026-10-26, fetch on several cores after in-place bodies (#1503)

`sh bench/perf/web/fetch.sh 3`, tree with #1495 and #1503, same machine and pinning (server CPUs 0-1, clients CPUs 2-3), two runs.

| Body, connections | Go req/s | Manuscript, tasks on one thread | Manuscript, 2 worker threads |
| --- | ---: | ---: | ---: |
| 3 bytes, 8 | 38.8k, 39.9k | 53.7k, 54.9k | 49.8k, 45.7k |
| 8 MiB, 1 | 268, 242 | 260, 252 | |
| 8 MiB, 8 | 425, 363 | 237, 202 | 590, 479 |

With the body received in place, two worker threads put the 8 MiB case 35-39% above Go's client on the same two CPUs. For tiny bodies the extra thread costs 7-15%, so keep one thread there.

## 2026-10-27, fetch framings and worker cost

`sh bench/perf/web/fetch.sh 3` on main at `946c4f4` plus this change, shared 4-CPU Linux VM (server on CPUs 0 and 1, client on 2 and 3), Go 1.24.7. Compare only within this run (±10%).

| Case (1 connection unless noted) | Manuscript req/s | Go req/s |
| --- | ---: | ---: |
| 8 MiB, Content-Length | 218 | 252 |
| 8 MiB, chunked | 110 | 167 |
| 8 MiB text, gzip | 90 | 578 |
| tiny, 8 connections | 46.1k | 47.3k |
| tiny, 8 connections, 2 worker threads | 45.2k | |
| tiny, 8 connections, client pinned to 1 CPU | 48.5k | 38.4k |
| tiny, 8 connections, 2 worker threads, client pinned to 1 CPU | 46.2k | |
| 8 MiB, 8 connections | 245 | 379 |
| 8 MiB, 8 connections, 2 worker threads | 570 | |

Chunked bodies (#1538): the decoder now receives a chunk's data straight into the result, as fixed-length bodies already did, and decodes framing straight into it. Client CPU for chunked 8 MiB reads fell from 0.45 s to 0.32 s of user time per 400 requests (`time`, client on CPUs 2 and 3). Throughput did not move because the Go server and the kernel copies bound it (sys time is 2.0 s of the 4 s run). gzip is bound by inflate, 6.9 ms of user time per 8 MiB (miniz_oxide); the extra copies are not what costs there, so a faster inflate backend is the remaining lever.

Worker threads on tiny bodies (#1539): with free cores, two threads match or beat one (45k to 63k req/s across runs, within noise of the single-thread number) at about 20% more CPU per request. Pinned to one CPU, two threads are 8 to 10% slower (46.6k against 51.8k in a separate three-round check), the 7 to 15% the issue saw: the cost is two threads time-sharing a core, not per-request work. `strace -c` shows the same system calls per request on one thread and on two, and each isolate has its own lock-free arena, so no shared structure showed up as the fixed cost. Crossover: use worker threads when there are at least as many free cores as threads; tiny bodies gain nothing from them, 8 MiB bodies gain 2.3x with two threads.

## 2026-10-27: Rust baseline, equal cores

`sh bench/perf/web/run.sh 4` on `90e401c4`, shared 4-CPU Linux VM, servers on 2 CPUs, load on the other 2. The earlier tables ran Manuscript on one worker against servers using both cores, which understated it by about 2x. Manuscript now runs two workers (`MS_THREADS`), and the hyper server in [`rust/`](rust) (two tokio workers, release with LTO) joins the comparison. Ranges cover both rounds.

| Measurement | Manuscript | hyper |
| --- | ---: | ---: |
| `/health` req/s | 113k–119k | 114k–119k |
| `/user/42` req/s | 107k–108k | 115k–116k |
| `/top?n=10` req/s | 53k–54k | 53k–56k |
| `/health` p99 | 2.2 ms | 1.9–2.7 ms |
| Resident memory after `/health` load (separate run) | 10 MB | 4 MB |
| Resident memory, 10,000 idle connections | 62 MB | 104 MB |
| `/health` req/s beside 10,000 idle connections | 105k | 111k |

Throughput and tail latency are at parity with hyper. `run.sh` prints resident memory after the `/io` rows, which hyper does not serve, so the printed 57 MB against 4 MB is not a comparison: the `/io` payloads and pool threads account for the difference (10 MB after `/health` load alone). The suite's Manuscript server also failed to compile on main (a discarded `Result` in the worker handshake) until this change.
