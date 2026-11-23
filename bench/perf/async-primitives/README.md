# Promise, pipe and timer primitives

A probe of the cost of one operation of the concurrency core, with Go and Rust (tokio) ports of the same program. It is a stress test of single primitives, not a headline benchmark; C has no task runtime to port it to. Each mode prints `mode total N ns/op X`.

| mode | one operation |
| --- | --- |
| `inline` | start a promise and wait for it |
| `batch` | start 64 promises, wait for each |
| `here` | the same as `inline` with `Placement.Here` (a task per promise) |
| `pingpong` | a round trip over two pipes between two tasks |
| `stream` | one value through a pipe to a consumer |
| `sleep` | a timer of zero (tokio's timer has 1 ms steps, so it has no column) |
| `echo` | a round trip on a loopback TCP connection |

```sh
ms build bench/perf/async-primitives/main.ms -o async && MS_THREADS=4 ./async inline 1000000
(cd bench/perf/async-primitives/go && go build -o async-go . && GOMAXPROCS=4 ./async-go inline 1000000)
(cd bench/perf/async-primitives/rust && cargo build --release && TOKIO_THREADS=4 target/release/async-primitives-rust inline 1000000)
```

## 2026-11-23 (x86-64 Linux sandbox, 4 cores, release `ms`)

Change: `proposals/fast-tasks-and-promises.md` (queue at one thread, wait parks on the row, wake a thread only when none is looking, sleeping threads in one word, start site in the row). Before is main at 3122af1e plus `claude/web-request-path` at 1d6d0683; after is that plus the change. Median of 9 interleaved runs, ns per operation at 1 / 4 threads.

| mode | before | after | Go 1.24 | tokio |
| --- | ---: | ---: | ---: | ---: |
| `inline` | 488 / 2,166 | 305 / 297 | 455 / 532 | 240 / 648 |
| `batch` | 316 / 2,540 | 268 / 260 | 423 / 698 | 182 / 525 |
| `here` | 481 / 538 | 441 / 435 | 448 / 560 | 238 / 656 |
| `pingpong` | 410 / 408 | 341 / 350 | 356 / 392 | 289 / 779 |
| `stream` | 61 / 61 | 62 / 53 | 48 / 50 | 76 / 64 |
| `sleep` | 253 / 247 | 213 / 203 | 377 / 375 | |

`echo` is not changed by this work (about 4.6 to 5.3 us in every column on that base).

Instructions (callgrind, one thread, `inline`): 4,640 per operation before, 2,896 after. System calls at four threads (`strace -c -f`, `inline 1000000`): 0.44 `write` and 0.45 `epoll_pwait` per promise before; voluntary context switches 114k before, about 1,200 after.

Controls, `bench/perf/promise-tree` (ms, median of 7, 1 / 2 / 4 threads, before then after):

| case | before | after |
| --- | --- | --- |
| `tree 36 15` (46k promises) | 300 / 60 / 30 | 78 / 46 / 25 |
| `tree 36 10` (514k) | 3,258 / 296 / 168 | 252 / 168 / 96 |
| `tree 36 5` (5.7M) | 28,186 / 2,731 / 1,559 | 2,243 / 1,486 / 837 |
| `fan 38 8` (8 promises of 150 ms) | 1,161 / 618 / 304 | 1,223 / 612 / 330 |

`fan 38 8` is eight `fib(38)` calls and no promise work to speak of; its one-thread row moves 5% with nothing but the program's layout changed, so the four-thread row is within that noise. A program that starts one promise and computes beside it still gets a second thread (four promises that sleep and then compute: about 45 ms before and after on four threads).

Not done: tokio is still faster at one thread (`inline` 240 ns). What remains per promise is the result's heap block, two closure objects and the cleanup entry; see stage 2 of the proposal.
