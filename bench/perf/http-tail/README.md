# HTTP tail latency

Compares p50 to max latency of the same HTTP server written in Manuscript, C, Go and Node. The C server is one `epoll` loop per core with its own listening socket (Linux only); it parses only the request line and sends no `Date` header, so it is a floor, not an equal.

- `server.ms`, `server.js`, `server.go`, `server.c`: build a JSON body of 64 items (4096 for `/big`) and reply. `/slow` first burns about 5 ms of CPU.
- `load.go`: open loop load generator. It sends on a fixed schedule over keep-alive connections and measures from the scheduled send time, so a stall is charged to every request it delayed. Requests to `/slow` and `/big` are left out of the numbers.

```
go build -o /tmp/load load.go && go build -o /tmp/goserver server.go && cc -O2 -pthread -o /tmp/cserver server.c
ms build server.ms -o /tmp/msserver
/tmp/msserver &  node server.js 8082 &  /tmp/goserver 8083 &
/tmp/load -addr 127.0.0.1:8081 -rate 2000 -conns 64 -slow 20 -dur 15s
/tmp/load -addr 127.0.0.1:8081 -rate 0 -conns 64 -dur 8s    # closed loop: requests per second
```

## Results, 2026-11-15, 4 vCPU Linux VM, load generator on the same machine

| Scenario | Server | p50 | p99 | p99.9 | p99.99 |
| --- | --- | --- | --- | --- | --- |
| Fast handlers, 4000 req/s, 64 conns (30 s, 3 runs) | Manuscript | 0.66 ms | 1.44 ms | 3.3 to 4.9 ms | 6 to 10 ms |
| | Go | 0.65 ms | 1.50 ms | 3.2 to 4.7 ms | 7 to 12 ms |
| Same, 1000 conns, 6000 req/s | Manuscript | 0.62 ms | 1.46 ms | 4.1 ms | 11.3 ms |
| | Go / Node | 0.58 / 0.59 ms | 1.58 / 1.83 ms | 3.7 / 4.5 ms | 8.8 / 6.9 ms |
| 5% of requests burn 5 ms CPU (every 20th), 2000 req/s | Manuscript | 0.72 ms | **5.12 ms** | 6.6 ms | 12.8 ms |
| | Go | 0.62 ms | 1.45 ms | 3.6 ms | 5.4 ms |
| | Node | 1.77 ms | 8.45 ms | 10.6 ms | 13.1 ms |
| 1 in 20 responses is 120 KB, 2000 req/s | Manuscript | 0.60 ms | 1.46 ms | 3.9 ms | 7.9 ms |
| | Go | 0.63 ms | 1.41 ms | 2.0 ms | 3.5 ms |

Findings: with fast handlers Manuscript matches Go and Node. A request that burns CPU delays every other request on the same worker thread (a connection stays on one worker, and a handler is not preempted), so the p99 rises to the handler time. Go moves goroutines between threads and does not show it.

## Results, 2026-11-16, connection stealing, same 4 vCPU Linux VM

"Before" is `main` at 688af5b7; "now" is 7d462817 with connection stealing. Servers alternated in one session, two rounds of 15 to 20 s per scenario, ranges shown; the machine is shared, so compare rows of this table only with each other.

| Scenario | Server | p50 | p99 | p99.9 |
| --- | --- | --- | --- | --- |
| 5% of requests burn 5 ms CPU, 2000 req/s | Manuscript before | 0.75 to 0.84 ms | 5.8 to 6.2 ms | 9.1 to 18.7 ms |
| | Manuscript now | 0.63 ms | **3.2 ms** | 5.5 to 5.7 ms |
| | Go | 0.65 ms | 2.9 to 3.2 ms | 5.7 ms |
| | Node | 2.5 ms | 10.8 to 15.9 ms | 16.7 to 28.4 ms |
| Fast handlers, 4000 req/s, 64 conns | Manuscript before | 0.67 ms | 1.8 ms | 6.0 to 6.8 ms |
| | Manuscript now | 0.67 ms | 1.5 to 1.9 ms | 3.9 to 11.3 ms |
| | Go | 0.66 ms | 1.7 to 1.8 ms | 5.2 to 6.5 ms |
| | Node | 0.68 ms | 1.9 to 2.2 ms | 6.0 to 7.5 ms |
| 1 in 20 responses is 120 KB, 2000 req/s | Manuscript before | 0.63 ms | 1.9 to 2.0 ms | 5.8 to 6.5 ms |
| | Manuscript now | 0.62 ms | 1.6 to 2.5 ms | 3.8 to 14.2 ms |
| | Go | 0.65 ms | 1.5 to 2.0 ms | 3.3 to 5.8 ms |
| 1000 conns, 6000 req/s | Manuscript before | 0.63 ms | 1.6 to 2.0 ms | 4.1 to 6.5 ms |
| | Manuscript now | 0.63 ms | 1.7 ms | 4.2 to 4.7 ms |
| | Go | 0.50 to 0.54 ms | 1.8 to 2.5 ms | 3.9 to 5.7 ms |

| Cost, fast handlers | CPU for 88,000 requests at 4000 req/s | Peak memory | Closed loop, 64 conns |
| --- | --- | --- | --- |
| Manuscript before | 5.2 to 5.8 s | 7.5 MB | 118k to 121k req/s |
| Manuscript now | 5.4 to 6.0 s | 6.4 MB | 112k to 113k req/s |
| Go | 9.6 to 10.1 s | 14.5 MB | 53k to 56k req/s |
| Node | 6.0 s | 69 MB | 24k req/s |

Findings: with a computing handler in the mix the p99 falls from the handler time to Go's level, and the p50 falls below Go's. Fast-handler latency, CPU and memory are unchanged within the noise of this machine. Closed loop on a machine the load generator shares is 2 to 6% lower (repeated fresh starts: 117k to 132k against 131k to 134k): a thread the operating system sets aside for a millisecond looks like a computing handler, so the watcher looks often (about 6% of one core) and idle threads take connections that needed no help.

## Results, 2026-11-16, C floor and idle spin, same 4 vCPU Linux VM

"Before" is `main` at d9dfcfad. "Now" adds two changes: a scheduler thread spins before it sleeps only while its waits are shorter than the spin (`spin_for_work` in `crates/ms-rt/src/task/reactor.rs`), and the content-type check of a response reads its 512 bytes without a branch per byte. Alternated runs, 15 s each, ranges over two or three rounds.

| | C | Manuscript before | Manuscript now | Go |
| --- | --- | --- | --- | --- |
| CPU for 60,000 fast requests at 4000 req/s | 1.6 to 1.9 s | 4.3 to 4.4 s | 3.5 to 3.6 s | 7.1 to 7.5 s |
| of which user / system, per 40,000 requests | 0.2 / 0.8 s | 1.9 / 1.0 s | 1.2 / 1.0 s | 2.6 / 1.7 s |
| Peak memory | 2.2 MB | 6.4 MB | 6.5 MB | 14.5 MB |
| Fast handlers: p50 / p99 | 0.66 / 1.6 to 2.3 ms | 0.67 / 1.6 to 1.7 ms | 0.67 / 1.5 to 1.8 ms | 0.66 / 1.7 ms |
| 5% slow requests: p50 / p99 / p99.9 | 0.76 / 6.0 / 9 to 14 ms | 0.63 / 3.1 to 3.7 / 5.3 to 5.8 ms | 0.64 / 3.4 to 3.6 / 5.5 to 7.5 ms | 0.65 / 2.6 to 3.1 / 5.2 ms |
| Closed loop, 64 conns | 176k to 191k req/s | 115k to 129k | 115k to 126k | 59k |

Findings: system time already equals C's. The user time left is the handler: `out = out + f"..."` costs about 1,000 instructions per item (a temporary string, an append, a free) against about 50 in C; callgrind attributes two thirds of the 100,000 instructions per request to it. Controls for the spin change (4 threads, median of 9, before / now): `promise-tree tree 36 10` 78 / 79 ms, `mailbox 100000 5` 148 / 146 ms.

## Results, 2026-11-16, instructions per request

Counted with callgrind (method: wiki): one scheduler thread, 8 keep-alive connections, closed loop, a handler that returns a 45-byte constant, `GET /x?c=N` with only a `Host` header. Instruction counts repeat to about 0.3%; wall clock on the shared VM does not.

| Server | Instructions per request |
| --- | --- |
| C (`server.c` with the body cut to nothing for `/x`) | 2.5k |
| Manuscript, `main` at 9f09fd55 | 19.3k |
| Manuscript, content-type check by 8-byte words | 18.4k |
| Manuscript, and detached request tasks | 15.9k |

Where the rest goes is in the proposal.

## Results, 2026-11-16, TLS and HTTP/2 connection stealing, same 4 vCPU Linux VM

"Before" is `3d8676894` (plain HTTP/1 stealing only); "now" adds idle TLS and HTTP/2 connections. Run with `HTTP_TAIL_TLS=<dir with cert.pem and key.pem> ./server` and `load -tls` (HTTP/1.1 over TLS) or `load -h2` (one HTTP/2 connection each, certificate not verified). 64 connections, 10 s after a 2 s warm-up; one run each for the slow mix, three for the fast mix. CPU is the server process's user plus system ticks over the run (100 per second).

| Scenario | Server | p50 | p99 | p99.9 | CPU ticks |
| --- | --- | --- | --- | --- | --- |
| TLS, 5% of requests burn 5 ms, 2000 req/s | before | 0.74 ms | 5.3 ms | 8.8 ms | 820 |
| | now | 0.64 ms | **3.6 ms** | 6.3 ms | 1045 |
| HTTP/2, same mix | before | 0.79 ms | 5.9 ms | 9.1 ms | 872 |
| | now | 0.68 ms | **3.4 ms** | 5.9 ms | 1077 |
| TLS, fast handlers, 4000 req/s | before | 0.66 to 0.68 ms | 1.6 to 8.8 ms | 3.3 to 36 ms | 267 to 288 |
| | now | 0.67 ms | 1.7 to 2.3 ms | 3.7 to 6.2 ms | 293 to 309 |
| HTTP/2, fast handlers, 4000 req/s | before | 0.54 to 0.57 ms | 1.8 to 1.9 ms | 3.5 to 3.7 ms | 389 to 400 |
| | now | 0.56 to 0.57 ms | 1.9 ms | 4.4 to 8.2 ms | 390 to 396 |

Findings: with a computing handler in the mix the p99 falls to about 3.5 ms for both, as for plain HTTP/1. The cost is CPU: the watcher now also looks while a TLS or HTTP/2 server computes (about 25% more with the slow mix, about 8% for TLS with fast handlers; HTTP/2 shows none). Fast-handler tails are the same within the noise of this machine; single runs of main and of the change each showed a 40 to 100 ms outlier.

### Review follow-up: the cost of listing connections, same day

Fast handlers (4000 req/s, 64 connections, 8 s after a 2 s warm-up), runs of `main` at `cb7f3a7a9` and the change interleaved; medians. `HTTP_TAIL_CORES=1` serves with one thread, so no thread has anything to take and the watcher does not run: what remains is the cost of parking an idle connection.

| Server | Runs | p50 | p99 | p99.9 | p99.99 | CPU ticks |
| --- | --- | --- | --- | --- | --- | --- |
| TLS, 4 threads, main | 16 | 0.679 ms | 2.38 ms | 5.21 ms | 7.4 ms | 236 |
| TLS, 4 threads, now | 16 | 0.676 ms | 2.32 ms | 5.41 ms | 7.5 ms | 253 |
| TLS, 1 thread, main | 6 | 0.692 ms | 2.52 ms | 5.84 ms | 8.0 ms | 152 |
| TLS, 1 thread, now | 6 | 0.693 ms | 2.61 ms | 5.66 ms | 9.5 ms | 157 |
| HTTP/2, 4 threads, main | 10 | 0.585 ms | 2.07 ms | 4.41 ms | 6.6 ms | 314 |
| HTTP/2, 4 threads, now | 10 | 0.583 ms | 2.09 ms | 4.52 ms | 6.8 ms | 324 |

Instructions per TLS request with one thread (`valgrind --tool=callgrind` on the server, closed loop over one connection, slope between runs of 3 s and 14 s counted by handler calls): 101.9k before, 102.7k now (+0.8%). So of the +7% CPU with four threads, about 3% is parking (the one-thread rows, +0.8% of it in instructions) and about 4% is the watcher and the steals. An earlier three-run reading of +4.4 ms p99.9 for HTTP/2 was noise: ten interleaved runs give 4.41 and 4.52 ms (single-run ranges 3.5 to 12.2 and 3.4 to 18.9 ms).

Closed item: the +3% CPU for parking was noise. Twelve interleaved one-thread TLS runs (4000 req/s, 64 connections, 8 s after a 2 s warm-up) of `main` before #4227 (`d2a4c5092`) and after it (`7df6fdce0`) gave 143.2 and 145.3 ticks on average (standard deviation 4.1 and 4.8), a difference of 1.5% with a standard error of about 1.4 ticks: not distinguishable from zero, and in line with the +0.8% in instructions. The earlier six runs per side could not resolve a 3% difference at this spread. Nothing to fix in the parking path.

Same day, `main` before and after #4227, medians of 5 interleaved runs (10 for the after rows of TLS and HTTP/2), 4 threads: fast handlers at 4000 req/s p99 / p99.9 / CPU ticks, and the slow mix (every 20th request burns 5 ms, 2000 req/s) p99 / CPU ticks.

| Server | Fast p99 | Fast p99.9 | Fast CPU | Slow p99 | Slow CPU |
| --- | --- | --- | --- | --- | --- |
| plain, before | 2.43 ms | 6.6 ms | 206 | 3.61 ms | 826 |
| plain, after | 2.72 ms | 5.1 ms | 208 | 3.42 ms | 829 |
| TLS, before | 2.55 ms | 7.4 ms | 235 | 6.25 ms | 686 |
| TLS, after | 2.29 ms | 4.5 ms | 249 | 3.54 ms | 856 |
| HTTP/2, before | 2.51 ms | 5.2 ms | 326 | 6.28 ms | 730 |
| HTTP/2, after | 2.33 ms | 5.9 ms | 340 | 3.89 ms | 894 |

No fast-handler regression; the slow-mix CPU rise (about 25%) is the watcher.

## Results, 2026-11-16, clock reads per request

Counted with an `LD_PRELOAD` shim on `clock_gettime(CLOCK_MONOTONIC)`: one scheduler thread (`MS_THREADS=1`), `server.ms` with a 30 s `HttpServerOptions.timeout`, 64 connections, `load -warm 0` so the request count covers the same window as the reads. Release build, shared VM; read counts repeat, throughput does not.

| Load | `main` at cb7f3a7a | #4229 |
| --- | --- | --- |
| 2000 req/s | 15.7 | 8.7 |
| closed loop | 11.4 | 4.2 |

Closed-loop throughput over 3 runs each: 40.7k to 51.3k req/s before, 44.2k to 50.7k after (no change within the noise). Without a timeout the closed loop reads about 0.

The 4.2 left, one each: the arrival stamp at parse; `late` after the handler (a handler that never switches is never killed, so only a read shows it ran past its deadline); the scheduler's per-round check while the handler's kill timer is armed; `settle_timeouts` before the reactor parks (a read after the deadlines it creates). Each is about 20 ns, under 3 percent of a request. Sharing one read per turn needs a non-blocking poll per turn, a 300 ns syscall to save 20 ns reads, so it was not built. A request count taken over a window shorter than the read count (the load tool's default 3 s warm-up) overstates reads per request by about 1.6.

## Results, 2026-11-16, text built piece by piece, same 4 vCPU Linux VM

"Before" is `main` at 9f09fd55. "Now": `out += f"..."` writes the pieces straight onto `out` (`msrt_string_append_fmtN`) instead of building the text and appending it.

| | C | Manuscript before | Manuscript now |
| --- | --- | --- | --- |
| User CPU for 40,000 fast requests at 4000 req/s, three alternated runs | 0.22 s | 1.33, 1.62, 1.50 s | 1.16, 1.38, 1.29 s |
| Instructions per item of the handler loop alone (callgrind, 200,000 items) | about 50 | 1,018 | 575 |

Findings: user time falls about 14%. What is left per item is one call for the `","`, one for the item, two integer renderings and a capacity lookup per call.

## Results, 2026-11-16, watcher look interval

The watcher looks every 2 ms and every 100 µs for 0.1 s after a thread was held up 1 ms; it sleeps after 20 looks with every thread resting (it was 100). Fixed intervals were swept against it (alternated runs of 12 s after a 2 s warm-up, three rounds, ranges; CPU is the server's user plus system time in 10 ms ticks per run, so compare rows of one table only; full table in the wiki):

| Look interval | Fast mix CPU | TLS CPU | Slow mix p50 / p90 / p99 |
| --- | --- | --- | --- |
| Two modes (kept) | 253 to 277 | 299 to 313 | 0.62 to 0.64 / 1.18 to 1.20 / 3.4 to 3.5 ms |
| 100 µs | 373 to 385 | 407 to 445 | 0.61 / 1.18 / 1.7 to 3.6 ms |
| 250 µs | 304 to 327 | 363 to 375 | 0.65 to 0.69 / 1.2 to 1.35 / 2.2 to 6.2 ms |
| 500 µs | 280 to 292 | 313 to 326 | 0.65 to 0.67 / 1.23 to 1.25 / 2.5 to 3.3 ms |
| 1 ms | 260 to 271 | 300 to 327 | 0.69 to 0.72 / 1.34 to 1.47 / 3.4 to 3.7 ms |

Findings: a single interval cannot keep the slow-mix p50 and p90 and the CPU at once, so the two modes stay (Chinmay: keep the previous latencies). The idle burst is what changed: a sleep that ended a rest left 100 looks (102 voluntary switches in an idle second, 2.5 to 2.9 ms CPU); now 20 looks (about 22 switches, 0.4 to 0.7 ms).

## Results, 2026-11-16, all four servers after the day's changes, same 4 vCPU Linux VM

`main` at 14a2a830. Servers alternated, three rounds, ranges shown; load generator on the same machine. Earlier sections were measured in other sessions, so compare rows of this table only with each other.

| Scenario | Manuscript | Go | Node | C |
| --- | --- | --- | --- | --- |
| 5% of requests burn 5 ms, 2000 req/s: p50 | 0.62 to 0.64 ms | 0.70 to 0.73 ms | 1.9 to 2.0 ms | 0.72 to 0.77 ms |
| same: p99 | 2.7 to 3.5 ms | 3.0 to 3.6 ms | 9.7 to 10.6 ms | 5.3 to 5.7 ms |
| same: p99.9 | 4.7 to 6.8 ms | 5.2 to 5.9 ms | 15 to 18 ms | 8.0 to 9.0 ms |
| Fast handlers, 4000 req/s, 64 conns: p50 | 0.69 ms | 0.67 to 0.69 ms | 0.71 to 0.72 ms | 0.67 to 0.69 ms |
| same: p99 | 2.4 to 2.8 ms | 2.0 to 2.8 ms | 2.8 to 3.3 ms | 2.1 to 2.8 ms |
| same: p99.9 | 4.5 to 8.6 ms | 4.3 to 6.0 ms | 6.2 to 8.0 ms | 4.4 to 8.3 ms |
| 1 in 20 responses is 120 KB, 2000 req/s: p99 | 1.9 to 2.7 ms | 2.3 to 2.6 ms | 3.0 to 3.3 ms | 1.9 to 2.6 ms |
| same: p99.9 | 4.4 to 5.5 ms | 5.6 to 10.0 ms | 5.7 to 6.5 ms | 4.5 to 7.3 ms |
| 1000 conns, 6000 req/s: p50 | 0.63 to 0.64 ms | 0.49 to 0.53 ms | 0.65 to 0.67 ms | 0.65 to 0.66 ms |
| same: p99 | 2.0 to 2.4 ms | 2.3 to 2.9 ms | 2.7 to 3.4 ms | 2.0 to 2.6 ms |
| same: p99.9 | 3.4 to 4.6 ms | 4.3 to 25 ms | 6.0 to 10.3 ms | 3.8 to 5.2 ms |
| CPU for 88,000 fast requests | 4.9 s | 10.3 to 10.9 s | 6.4 to 6.6 s | 2.4 to 2.6 s |
| Peak memory | 6.8 MB | 14.5 MB | 68 MB | 2.2 MB |
| Closed loop, 64 conns | 132k to 139k req/s | 46k to 50k | 19k to 26k | 170k to 180k |

Findings: Manuscript is at or ahead of Go and Node on every row except the 1000-connection p50, where Go is lower (not explained). The C floor (which parses only the request line and sends no `Date`) still uses about half the CPU and a third of the memory and serves about 30% more requests per second. A first pass earlier the same day on a14f74a7 (before the header and poll path changes) gave 4.5 s CPU and 113k to 126k closed loop for Manuscript, with C at 2.2 to 2.4 s and 162k to 183k, so the CPU figure moves by about 10% between sessions on this machine; the per-request instruction counts in `bench/perf/counts.txt` are the stable measure (six-header request 23,965 to 15,824; C about 2,474).
