# Baselines for the C runtime rewrite

The "to record" numbers of the targets table in `proposals/c-runtime.md` and the plan, measured on the Rust runtime so each stage of the rewrite can be compared with them. Rerun a stage with:

```sh
MS=./target/release/ms sh bench/perf/c-targets/run.sh <stage-name> [build hello tasks ws tls web suite]
```

Each measure prints `<stage> <key> <value>` lines. `ws` and `tls` run `server/` (one scheduler thread) and a Go client that opens N connections and holds them; the figure is the slope of the server's resident memory between a low and a high connection count, so the fixed base cancels. Linux only.

## 2026-11-20, Rust runtime at `fd2c28aa`

Machine: 4 vCPU Linux VM (shared), release `ms` (LLVM). Compare numbers only from the same machine.

| Measure | Baseline | Target |
| --- | --- | --- |
| Idle websocket connection (1 thread, 2k to 10k) | 6.6 KB resident + 1.0 KB page tables | 3 KB, then 1 KB |
| Parked task (100k `sleep` tasks, hibernated) | 2.4 KB resident + 1.0 KB page tables; spawn 0.3 s | 0.5 KB |
| Idle TLS connection, HTTPS keep-alive (rustls, 1k to 5k) | 8.1 KB resident, 15 bytes page tables | no worse |
| Hello-world binary, start-up | 720 KB, 2.4 ms (min of 25) | no larger, no slower |
| Cold build of the runtime (`cargo xtask runtime`, 4 vCPU) | 130 s (2 min 10 s) | under 30 s |
| Cold build of `ms-cli` after the runtime | 112 s | |
| `/health` req/s, 2 server threads, 64 connections | 252k (Go 130k, hyper 205k, C epoll 185k to 206k) | 1.2x by end of Phase A |
| `/user/42` req/s | 250k to 259k (Go 129k, hyper 201k, C 190k to 195k) | |
| `/top?n=10` req/s | 99k to 103k (Go 53k, hyper 99k) | |
| `/health` beside 10,000 idle connections | 212k; server resident 96 MB (Go 201 MB, hyper 104 MB) | |
| `/health` during `/io` | 106k, p99 2.0 ms (Go 5.9k) | |
| Idle system calls in 5 s | 23 (Go 7, hyper 0) | |

Note: the parked-task cancel took 41.5 s for 100k tasks in this run (0.4 s in the 2026-11-04 page); not investigated, likely a regression worth its own issue.

### Suite against C

Whole programs, min of 5, ms over C (below 1 is faster than C). "Checked" adds `-fsanitize=bounds,signed-integer-overflow -fsanitize-trap=all`, which traps fixed-size array bounds and integer overflow but cannot check bounds of `malloc`ed buffers, so it is a partial stand-in for fully checked C.

| Program | ms (ms) | C -O2 (ms) | ms / C | Checked C (ms) | ms / checked C |
| --- | ---: | ---: | ---: | ---: | ---: |
| csvgroup | 90 | 57 | 1.58x | 45 | 1.73x |
| dedupe | 224 | 294 | 0.76x | 258 | 0.75x |
| grep | 35 | 30 | 1.17x | 23 | 1.57x |
| jsonsum | 140 | 177 | 0.79x | 171 | 0.82x |
| logstats | 46 | 51 | 0.90x | 52 | 0.98x |
| pargroup | 14 | 17 | 0.82x | 18 | 0.94x |
| report | 132 | 159 | 0.83x | 127 | 1.03x |
| sortrecords | 186 | 327 | 0.57x | 279 | 0.71x |
| treegrep | 27 | 22 | 1.23x | 21 | 1.38x |
| wordfreq | 195 | 173 | 1.13x | 179 | 1.08x |

These ten programs already sit between 0.6x and 1.7x of C. The plan's "1.6x to 3.3x" text and collection figures come from other programs than the ones that have C versions here; the suite has no checked-C ports for them yet, so that row of the targets table still lacks a reproducible baseline.
