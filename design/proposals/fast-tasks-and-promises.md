# Fast tasks and promises (design proposal)

## Summary

- Problem: starting a promise and waiting for it costs 4,640 instructions and 520 ns on one thread (tokio 250 ns, Go 390 ns), and 2,300 ns on four threads, where each start pays a wake system call.
- Change: an unstarted promise is a queue entry at every thread count and becomes a task only when something must switch to it; a wait parks the task on the promise row itself; small results live in the row; a start wakes a thread only when no thread is already looking for work.
- Decided (Chinmay, 2026-11-23): a fault report's `task started by:` names only the program line that started the work. Nothing else observable changes.

## Status

- Stages 1, 3 and 4 and the start-site part of stage 2 built 2026-11-23 on main at 3122af1e plus `claude/web-request-path`; results in `bench/perf/async-primitives/README.md`. Results in the row (rest of stage 2) is not built. Direction (Chinmay, 2026-11-23): tasks, promises and the reactor must be the fastest primitive; root causes, data-oriented, portable.
- Built after the stages (2026-11-23, main at 3b93082f): the scheduling files compile as one unit, and a start reads no clock (design 8); the start line is a compile-time constant (design 5). Results in the same README.
- Scope split with `design/proposals/web-request-path.md`: that proposal owns sockets, HTTP and the edge poller. This one owns `core/` tasks, promises, parks, the work queue and the wake rule.

## Problem

Measured with `bench/perf/async-primitives` (release build, 4-vCPU VM, ns per operation at 1 / 4 threads, Go and tokio ports of the same program):

| Operation | Manuscript | Go | tokio |
| --- | ---: | ---: | ---: |
| start a promise, wait for it | 520 / 2,300 | 390 / 580 | 250 / 645 |
| start 64, wait for each | 380 / 2,600 | 550 / 850 | 190 / 530 |
| round trip over two pipes | 360 / 410 | 340 / 390 | 250 / 780 |
| timer of zero | 270 | 345 | n/a |

Callgrind, one thread, start plus wait: 4,640 instructions, flat. The costs that have a cause:

- One thread never queues (`queue_work` returns false at `ms_workers_limit() <= 1`), so every promise gets a stack, a task record and two switches even when its creator waits at once. Removing that one test (spike): 3,330 instructions, 319 ns.
- `promise_row_of` runs about 20 times per promise (351 instructions): every layer revalidates the id, and each call reads the scheduler through TLS to learn its own isolate.
- `capture_started` walks the stack and allocates on every start (about 420 instructions) for a report only a fault reads.
- A result travels through a heap block (`ms_promise_put` allocates, `ms_promise_take` frees), and a wait allocates and frees a token: about 600 instructions of allocator and token work.
- Four threads: `ms_workers_nudge` wakes a sleeping thread on every start (0.44 `write` and 0.45 `epoll_pwait` per promise under `strace -c`). The woken thread may not take work younger than 20 us, finds it gone and sleeps again: 1.8 s user and 3.6 s system for 0.56 s of work, 114k voluntary switches per million promises.

## Design

One rule: work is a row until something must switch to it. A promise is a table row and a closure; a task (stack, record, two switches) exists only for work that outlives its creator's turn.

1. Unstarted work at every thread count. `promise(fn)` with `Placement.Any` always queues. A waiter claims its entry and runs it on its own stack under a guard, as it does today above one thread. When only one thread may run, the scheduler starts the queued entries as tasks, oldest first, at the creator's next switch away, which is the first moment a task started eagerly could have run. Order, cancellation, limits and fault isolation are unchanged.
2. Rows resolve once. Each `msrt_promise_*` entry validates the id once and passes the row index down; `promise_row_of` is an inline function over a table that holds its isolate tag. The queue entry is found by a sequence number kept in the row, not by a scan.
3. A wait parks on the row. `Hot.token` holds a wait word: the handle of the parked task with the top bit set, or a token id for `wait_any`, groups and waiters on another thread. `ms_token_post` of a wait word wakes the task. The scheduler counts parks that another thread ends, as it counts remote tokens today, so deadlock detection is unchanged.
4. Results in the row. A value of at most 24 bytes is stored in the cold row; larger values keep the heap block. `io_done_int` and `io_done_unit` allocate nothing. The pipe unread hook and cross-thread mail keep the block form.
5. Start site as a constant. `promise` takes `site: String = caller_frame()`; the compiler passes the call's `file:line in function` as a literal and the row keeps it, so a start walks no frames (decision above; Chinmay, 2026-11-23: no cost for it at all). An earlier form read 8 return addresses off the frame chain: 205 of 2,169 instructions. Walking and copying up to 64 frames was 30% of `promise-tree tree 30 10`.
6. One wake rule. Threads have three rest states: running, looking (a timed wait for queued work to age) and asleep. A start wakes a thread only when none is looking; a looking thread that keeps finding nothing doubles its interval from 20 us up to 200 us and falls asleep after 20 empty looks. A thread that takes work stops looking and wakes the next one if more is queued. Sleeping threads are bits of one word, so a start that finds none asleep reads one word. This is the spinning-thread rule of Go and tokio with a timed wait in place of a spin.
7. A waiter that is not a promise. `ms_sched_fd_notify(kind, id, fd, events)` adds a descriptor waiter that calls a function registered once per `kind` (a small per-scheduler table; the node stays 24 bytes and holds no pointer). The web path's idle-connection watch uses it in place of `new`, `io_on_ready`, `fd_ready` and `drop`.
8. A start reads no clock. A queue entry carries no push time. A look (an idle thread reading a queue) dates the entries no look has seen, and takes the oldest once it was first seen a beat ago. A thread woken by a start looks at once, so the work waits one beat as before; a thread already looking takes it up to one rest later than before. The owner pays nothing.

Semantics kept: a promise still starts without a wait (stage 1's switch rule, the looking thread above one thread); dropping a promise cancels and joins; a fault ends only its promise; `Placement.Here` and `Spread` are unchanged.

Targets, by `bench/perf/async-primitives` and callgrind: start plus wait at most 1,500 instructions and at most tokio's time on one thread; four threads within 1.2x of one thread with under 0.01 system calls per promise; pipe round trip at most Go's; no case in `bench/perf/promise-tree`, `small-promises` or `bench/perf/web` slower.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/runtime/core/promise*.c`, `promise_table.h` | row-based internals, waiter word, inline results, start-site ring | `promise-*`, `pipe`, `cancel` fixtures; `core_unit` |
| `src/runtime/core/queue.c`, `worker.c`, `isolate.c` | queue at one thread, sequence lookup, looking state and wake rule | `promise-cross-thread`, new unit tests for the wake rule; `MS_SCHED_STRESS=1` corpus run |
| `src/runtime/core/task.c`, `park.c`, `token.c` | start queued work at a switch; park on a row; `ms_sched_fd_notify` | `core_unit`, `http-*` fixtures |
| `bench/perf/async-primitives` | the probe with Go and tokio ports and a dated result | `make bench-check` |

## Alternatives

- Do nothing: 2x tokio on one thread and 4x Go on four for the primitive everything else is built on.
- Trim only (inline `promise_row_of`, pool the token): measured ceiling is the 20% those functions cost; the stack per promise and the wake per start stay.
- Stackless promises (compile `fn` bodies to state machines): removes stacks entirely, but it is a language and compiler change with function colouring; out of scope here.
- Wake nobody at a start and let the creator wake helpers when it waits or parks: a creator that starts one promise and then computes would never get a helper (the #4112 regression).
- Spin instead of a timed look: measured before at 660 ms of CPU for a 190 ms run (`bench/perf/small-promises`).

## Stages

1. Queue at one thread, rows resolve once, wait parks on the row (design 1 to 3). Check: instructions and ns for start plus wait and pipe round trip; conformance `run` and `test` counts unchanged.
2. Results in the row and the start site in the row (4, 5). Check: zero allocations per start plus wait of an `Int`; `e2e/stdlib/promise-fault-started-line`.
3. The wake rule (6). Check: four-thread rows of the probe, system calls per promise, `promise-tree` and `small-promises` at 1, 2 and 4 threads, the fan-out-of-waiters test.
4. `ms_sched_fd_notify` (7), adopted by the web path. Check: instructions per request in `bench/perf/web`.
