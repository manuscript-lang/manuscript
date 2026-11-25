# Web request path at C speed (design proposal)

## Summary

- Problem: one-core `/health` runs at about 65k req/s against C's 115-190k and hyper's 125k. Per request it spends 6.3 us user and 8.7 us kernel, against C's 0.4 us and 5.0 us, and makes 1.2 context switches where C makes none.
- Change: a request touches only memory its connection owns (zero steady-state allocations), is read and written by the thread that owns the connection (no loop thread, no handoff), and costs 2 syscalls amortised with one batched readiness wait.
- Decision requested: approve the stages below. No language, stdlib API or `HttpRequest` change.

## Status

- Stages 1 and the Linux, one-thread part of 3 landed 2026-11-23 (24.4k to 14.3k instructions per request; `bench/perf/results.md#web`); stage 2's handler-in-connection-task, multi-thread edge reads, kqueue and Windows remain. Proposal, 2026-11-23, main at 642ba74c. Direction (Chinmay, 2026-11-23): beat the Rust ms and reach C speed, with better data structures and algorithms, no patch fixes.

## Problem

Measured on this 4-CPU VM (server on CPU 0, loadc on CPUs 1-3, 128 connections, `bench/perf/web`, release build, noise about 15%):

| | req/s | user us/req | kernel us/req | syscalls/req |
| --- | ---: | ---: | ---: | ---: |
| C (`c/server.c`) | 115-190k | 0.4 | 5.0 | 2.0 |
| Manuscript (main) | 62-72k | 6.3 | 8.7 | 2.4 (+0.2 epoll_pwait, 0.03 futex, 0.03 ppoll, 0.02 io_uring_enter) |

C is a floor, not a like-for-like target: level-triggered, 4 KiB buffer, no cancel, deadline, fault isolation, TLS or h2 (`c/server.c:3-4`). The generator saturates near 185k. Per-thread split at 1 CPU (`/proc/<pid>/task` over 3 s, about 200k requests): the runtime thread has 108 user and 15 system ticks and 124k voluntary switches; the loop thread has 19 user and 159 system ticks and 123k involuntary switches. So the loop thread does the socket syscalls and every request crosses two threads on one CPU: 1.2 switches per request (measured). The direct reads and writes of #6682 and #6684 are gated off at one isolate and moved 1 CPU only 72k to 74k, so the handoff is removed only by taking the loop thread off the data path, not by trimming it.

Callgrind of the Manuscript server (61,594 requests, `/health`, main at 642ba74c): 24.4k instructions per request including the loop thread (the 2026-11-12 figure of 12.7k was the Rust implementation; hyper is 6.7k). 6.3 us is about 19k cycles, consistent with 24k instructions at IPC 1.3 under cold-cache switching.
- Allocation, list growth and strings: 8.0k (33%). `ms_list_extend_grow` runs 16 times per request (reply and request staging, string builders, the cleanup list), `ms_headers_copy` 3 times, `ms_string_from_span` 11 times.
- Tasks, cleanup and scheduling: 4.6k (19%). 14 `msrt_cleanup_push` per request, one task per request (`request_task`, `ms_task_join`), 6 task switches.
- Parse and serve: 4.2k (17%): llhttp 605, `ms_http_target_parse` 600, `ms_http_detect_content_type` 301.
- Network and libc: 3.2k (13%).

The kernel excess is not extra reads or writes (2.4 against 2.0 per request): it is the 1.2 switches and the eventfd, `epoll_pwait` and futex traffic of the loop thread.

## Design

One rule: the connection is the unit of ownership. Everything a request needs lives in the connection's two flat buffers and a request arena that resets when the response is written.

1. Readiness. Each scheduler thread already owns a libuv reactor (`io/reactor.c`) whose watches are one-shot, so each wait costs an `epoll_ctl` pair (measured in the WIP branch `claude/runtime-inline-reads`: no gain). The change is a raw edge-triggered poller. A connection is registered once, at accept, edge-triggered for read and write (epoll `EPOLLET`, kqueue `EV_CLEAR`), and never modified. Per connection a row holds the fd, two sticky ready bits and the parked waiter. A read tries `read` first; on `EAGAIN` it clears the bit and parks; a short read clears the bit without a second `read`. Hang-up and error events set the same sticky bit, so a close is never missed. Close, cancel and a stolen connection (`http_serve_steal.c` re-registers the row on the new thread, whose `EPOLL_CTL_ADD` reports pending data as a fresh edge) run on the owner thread, which replaces the ordering the loop thread provided (`direct`, `reads_posted`, `broken`). TLS and HTTP/2 use the same rows for readiness; only decryption differs. The scheduler polls with timeout 0 when tasks are runnable (every N switches) and blocks only when idle. The accepting thread owns the connection for life: no cross-thread wake. Windows keeps the libuv poll row behind the same interface (`sys/`), so behaviour is at parity.
2. Memory. The connection owns an input buffer, an output buffer and an arena. The parser writes method, target and headers as spans into the input buffer (a flat table, no per-header string). `HttpExchange` accessors build their owned `String` or `Headers` lazily and only when the handler calls them. The response head is formatted into the output buffer with a precomputed length and sent with the body in one write. The buffers persist across requests.
3. Tasks. The handler runs inside the connection's task under a guard (fault becomes a 500, cancel unwinds), not in a new task joined per request. A task's cleanup records live in one contiguous per-task stack with capacity kept across requests; a push is a store and an increment, inlined by the compiler.
4. Content type and routing facts (`ms_http_detect_content_type`, target parse) run once on the bytes already in the input buffer and are skipped for a status line with no body.

Targets, measured per request with callgrind, strace and context-switch counts, with req/s as the final check: instructions at or below hyper's 6.7k after stage 2 and 3k as the stretch; at most 2.1 syscalls; 0 allocations after warm-up; 0 context switches, futex and eventfd writes on the 1-CPU path; 1-CPU req/s at least hyper's, then at least 0.9 of C.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/runtime/sys/` | edge-triggered poller: epoll, kqueue, libuv row (Windows) | `net`, `http-*` conformance on all six platforms |
| `src/runtime/io/reactor.c`, `core/sched.c` | per-thread poller owns connection rows; batched poll between task switches | `net-close-releases-socket`, `promise-*` fixtures |
| `src/runtime/std/net_conn.c`, `net_core.c` | read and write on the owner thread; loop thread keeps listen, DNS, TLS and pipes | `leak_check`, cancel and close fixtures |
| `src/runtime/std/http_serve_*.c`, `http_exchange.c` | span-based request table, connection buffers, arena, single-write response | `http-*` fixtures, `bench/perf/web` |
| `src/runtime/core/unwind.c`, `compiler/lower` | contiguous cleanup stack, inlined push and discard | compiler conformance, `ownership-fuzz` |
| `stdlib/net/http.ms` | `serve_buffered` and the worker body only (internal; no exported change) | tutorial and stdlib example tests |

## Alternatives

- Do nothing: 0.5x of C and 0.55x of hyper at one core; the stated goal is C speed.
- Trim the current path (fewer cleanup pushes, pooled lists): measured gains of 4-6% per cut (bench/perf/results.md#web, 2026-11-12); the C ceiling needs the structure above, not 30 cuts.
- Keep the libuv loop thread and add direct reads and writes (#6682, #6684): fixed 2 and 4 CPUs (73k to 156k and 228k) and cannot help one CPU, where the cost is the loop handoff and 24k instructions.
- io_uring: Linux only, no parity; the portable poller gives the same syscall count.
- Run the scheduler's own libuv poll with per-wait registration (tried, WIP branch `claude/runtime-inline-reads`): no gain beyond noise, because each wait is an `epoll_ctl` pair.

## Stages

1. Connection buffers, span request table, lazy accessors, single-write response (local to `http_*.c`, no parity risk). Check: allocations and instructions per request.
2. Handler in the connection task; contiguous cleanup stack. Check: instructions per request, fault and cancel fixtures.
3. Edge-triggered poller on Linux first (spike behind the existing interface, steal, cancel and close fixtures green), then kqueue and the Windows libuv row. Check: context switches and syscalls per request at 1, 2 and 4 CPUs on every platform.
4. Dated `bench/perf/results.md#web` section against C and hyper at 1, 2 and 4 CPUs, with the counts.

Each stage lands green and records its counts; the proposal ships in the PR of the first stage. Review (independent, 2026-11-23): build with changes; the changes above (measured switches, reordered stages, steal and hang-up rules, ratio targets) are applied.

## Open questions

- Whether the contiguous cleanup stack (stage 3) is a compiler-wide change worth its own proposal; recommendation: keep it in this one only if stage 2 does not reach 3k instructions.
