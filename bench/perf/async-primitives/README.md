# Promise, pipe and timer primitives

A probe of the cost of one operation of the concurrency core, with Go and Rust (tokio) ports of the same program. It is a stress test of single primitives, not a headline benchmark; C has no task runtime, so `c/main.c` is a floor for `inline` only: a row table, a locked queue and a heap closure, run by the caller. Each mode prints `mode total N ns/op X`.

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

Change: `design/proposals/fast-tasks-and-promises.md` (queue at one thread, wait parks on the row, wake a thread only when none is looking, sleeping threads in one word, start site in the row). Before is main at 3122af1e plus `claude/web-request-path` at 1d6d0683; after is that plus the change. Median of 9 interleaved runs, ns per operation at 1 / 4 threads.

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

### Later the same day: small results stay in the row

Stage 2 of the proposal: a result of at most three words is stored in the promise row, so a start and wait allocates no result block. Same machine and method.

| `inline` | ns at 1 / 4 threads | instructions |
| --- | ---: | ---: |
| before the change | 488 / 2,166 | 4,640 |
| stage 1 | 305 / 297 | 2,896 |
| stage 2 | 233 / 236 | 2,575 |
| Go 1.24 | 455 / 532 | |
| tokio | 240 / 648 | |
| C floor (`c/main.c`) | 31 | 270 |

The C floor has no cancellation, no fault report, no placement and no second thread; it is the cost of the row, the queue and the closure alone. What separates the two is mostly runtime calls per promise (create, start, wait, take, free are separate entries) and the closure objects the compiler builds per start.

### Later the same day: the scheduling files inline, and a start reads no clock

Before is main at 3b93082f; after adds two changes. The task, promise and queue files compile as one unit, so the calls between them inline. A queued start no longer reads the clock: an entry is dated by the first idle thread that sees it and may be taken a beat after that. Same machine; median of 9 interleaved runs, ns per operation at 1 / 4 threads.

| mode | before | after | C floor |
| --- | ---: | ---: | ---: |
| `inline` | 246 / 260 | 204 / 214 | 33 |
| `batch` | 213 / 238 | 169 / 188 | 26 |
| `here` | 400 / 405 | 395 / 387 | |
| `pingpong` | 330 / 336 | 303 / 331 | |

Instructions for `inline` at one thread: 2,637 before, 2,402 after; the C floor is 270. (The stage 2 row above read 233 ns for the same code as this section's 246: the machine's load differs between sessions, so compare within a table.)

Controls, `bench/perf/promise-tree` (ms, median of 7, 1 / 2 / 4 threads):

| case | before | after |
| --- | --- | --- |
| `tree 36 15` | 79 / 46 / 26 | 68 / 44 / 24 |
| `tree 36 10` | 224 / 161 / 94 | 197 / 136 / 88 |
| `fan 38 8` | 1,226 / 612 / 314 | 1,187 / 626 / 310 |

One promise of `fib(36)` beside the same call on the starting thread still gets a second thread: 74 to 94 ms before and after, against 116 to 158 ms at one thread.

Tried and dropped: one runtime call for wait plus take, and one for end plus drop. No change in instructions; the cost is inside the calls, not between them.

Not done. `inline` is still about six times the C floor. Where the 2,402 instructions go: recording the start site 205; the queue entry (push, claim, remove, started list) about 270; the row's life (new, put, take, end, drop) about 540; the second closure the standard library wraps around the work about 250; the guard around the inline run about 110; cleanup registrations and the shield in compiled code about 380; the `Int!` result, which is 12 words and is copied three times in the caller. The guard, the registrations and the result layout belong to the compiler's return-path work.

### Later the same day: one closure per start

The optimizer fuses the closure the standard library wraps around the work with the work's own closure (`opt_inline_capture.c`): one object per start, and the work inlines into the wrapper. Before is the section above; median of 9 interleaved runs, ns at 1 / 4 threads.

| mode | before | after | C floor |
| --- | ---: | ---: | ---: |
| `inline` | 204 / 215 | 186 / 180 | 33 |
| `batch` | 173 / 173 | 143 / 154 | 26 |

Instructions for `inline` at one thread: 2,402 to 2,169. Allocations per start and wait: 2 to 1 (`tests/checks/ownership-counts/promise_wrapper_closure.ms`).

### Later the same day: the start line is a constant

`promise` takes `site: String = caller_frame()`: the compiler passes the line of the call as a literal, and the row keeps the two words of that string. A start no longer walks the stack. The fault report's `task started by:` line reads the same. Before is the section above; median of 9 interleaved runs, ns at 1 / 4 threads (the machine was quieter than for the section above, so compare within this table).

| mode | before | after | C floor |
| --- | ---: | ---: | ---: |
| `inline` | 147 / 148 | 141 / 137 | 33 |
| `batch` | 125 / 140 | 113 / 130 | 26 |

Instructions for `inline` at one thread: 2,168 to 1,914.

### Later the same day: the owner removes its queue entry without the lock

Three changes to the path of a start that its own waiter runs:

- The owner takes its entry back with one compare-and-swap on the entry (`ms_queue_remove`), not under the queue's lock; the ring is indexed by sequence number, and removed entries are trimmed at the next push or look.
- Freeing an empty fault report and an empty start line is an inline test.

Before is the section above; median of 9 interleaved runs, ns at 1 / 4 threads.

| mode | before | after | C floor |
| --- | ---: | ---: | ---: |
| `inline` | 134 / 136 | 121 / 124 | 33 |
| `batch` (4 threads) | 124 | 102 | 26 |

Instructions for `inline` at one thread: 1,914 to 1,750. `bench/perf/promise-tree` `tree 36 10` against the build of the one-closure section (ms, median of 7, 1 / 2 / 4 threads): 160 / 114 / 64 to 145 / 79 / 55.

### Later the same day: five runtime calls per promise, not seven

- A start makes the promise: `msrt_promise_start(work, site)` returns the id and calls the work with it, so `msrt_promise_new` is gone and the closure no longer captures the id.
- Dropping a promise is one call: `msrt_promise_close` ends the work and frees the row unless a result is left to take.
- A result of one, two or three words is copied in and out of the row without a `memcpy` call.

Before is the section above; median of 9 interleaved runs, ns at 1 / 4 threads (the machine was noisier than for the section above, so compare within the row).

| mode | before | after | C floor |
| --- | ---: | ---: | ---: |
| `inline` | 130 / 123 | 121 / 119 | 33 |
| `batch` (4 threads) | 111 | 102 | 26 |

Instructions for `inline` at one thread: 1,750 to 1,626. `bench/perf/promise-tree` `tree 36 10` (ms, median of 7, 1 / 2 / 4 threads): 142 / 78 / 67 to 133 / 72 / 61.

Correction before merging: both sections above were measured with one more cut, a guarded inline run that registered no cleanup for its closure. That cut is not in the change. The closure's entry is also what puts the guard's base above the promises the waiting frame started, so a fault or cancel inside the run does not end them; without it `yaml` and `http-fault-leak` timed out on windows-amd64 (3 of 3 runs, 0 of 5 with the entry). With the entry back `inline` is 1,706 instructions, not 1,626, and the times above are a few nanoseconds optimistic.

Not done. `inline` is 1,706 instructions against the C port's 270. The profile is flat: no function is above 80. About 900 are the promise and queue functions (five runtime calls per promise: start, wait, put, take, close), about 250 are cleanup registrations and the shield in compiled code, 90 the guard.

### Later the same day, another machine: no locked instruction where one thread writes

The sandbox moved to a slower host (Xeon 2.1 GHz, 4 cores): the same binaries read 35 ns for the C port and 168 ns for the section above. Locked instructions cost about 9 ns each here, which is why Manuscript lost more than C did. Before is `main` at 0e7a6010; minimum / median of 15 interleaved runs.

- The shield depth and the `unwinding` flag are written only by the task's own thread, so they change with a load and a store. They were an atomic add, an atomic subtract and an exchange: three locked instructions per promise, and two per shielded close anywhere. This is 27 of the 53 ns.
- The owner pushes to its queue without the lock: it writes the slot and publishes it by storing `tail`. `head` moves only under the lock, past entries taken or removed; the owner takes the lock when the ring looks full.
- `Promise.wait` is one runtime call, `msrt_promise_result`, which waits and moves the value out of the row the wait found. Taking the result frees the row, so the drop of the promise finds nothing to do.
- The calls between the promise, task and queue files that the unit build left as calls are forced inline (46 calls per promise to 27), a wait looks the row up once, and the task's deadline is written only when a wait has one.

| mode | before | after | C floor |
| --- | ---: | ---: | ---: |
| `inline`, 1 thread | 168 / 172 | 115 / 119 | 35 |
| `inline`, 4 threads | 169 / 192 | 117 / 136 | 35 |
| `batch`, 4 threads | 140 / 148 | 103 / 111 | |

Instructions for `inline` at one thread: 1,706 to 1,323. On the first machine of this page that count was 121 ns at 1,626, so this should read under 100 ns there; it was not rerun there.

Not done. Of the 1,323 instructions about 240 are three cleanup registrations (two in compiled code, one around the inline run), which go away when cancel exits replace the cleanup stack; 90 are the guard and 60 the shield. The two locked instructions left are the queue's: the store that publishes a push, ordered against a looker's last look, and the compare-and-swap that decides between the owner and a thief.
