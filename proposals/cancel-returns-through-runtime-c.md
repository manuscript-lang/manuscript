# A cancel returns through runtime C (design proposal)

## Summary

- Problem: a cancelled wait jumps to the task's guard and skips every runtime C frame in between. Whatever such a frame holds leaks unless that site registered it beforehand, and each leak found so far was one site that had not.
- Change: runtime C never unwinds past its caller. A cancelled wait answers a status like a timeout does, each frame frees on its ordinary error path, and the call ends at one place: where compiled code receives the status.
- Nothing a program can observe changes. `ms_lint` enforces the rule, so a new jump fails the build.

## Status

- Direction (Chinmay, 2026-11-23): structural fixes for leaks, not one patch per leak.
- Stage 1 (core waits, the lint rule) ships with this proposal. Stage 2 (the status, net, TLS, HTTP, files, terminal) follows.

## Problem

The C runtime ends a cancelled wait with `ms_cancelled()`, a jump to the task's guard that runs the task's cleanup stack. Compiled code is safe: the compiler registers what each frame owns. Runtime C is not: a frame that holds a block across a wait must call `ms_cleanup_push` first and `ms_cleanup_discard` after, by hand.

Counts on main at 2b72bde6: 16 `ms_cancelled()` sites and 11 callers of the jumping `ms_net_finish`, against 19 `ms_cleanup_push` sites in `runtime/std` (22 in all of `runtime`). The jump happens in inner layers (`ms_net_finish`, `ms_fail_finish_at`), so every caller above them is exposed, including C tasks such as the HTTP server's connection loop and the HTTP/2 writer. Leaks found by forcing a cancel at each park (`MS_CANCEL_AT_PARK`, stats build):

| Site | Held across the wait | Lost per cancel |
| --- | --- | --- |
| `serve_request`, `ms_exchange_finish`, `refuse` (#6782) | the exchange, the built head | 7 blocks per server close |
| `writer_body` in `http_serve_h2.c` (#6774) | the output bytes | 1 block |
| `read_file` job (#6716) | the file buffer | 16 MB |
| `net_dns_client.c` | the query state | found earlier, 8 registrations added |

Each fix was correct and each was one more remembered registration. The next C function that waits while holding something leaks again, and only a sweep that happens to cancel at that park finds it.

The frozen Rust runtime had the rule this proposal restores ([natives end a cancelled call by returning](../wiki/runtime/natives-end-a-cancelled-call-by-returning.md)); the C port kept the compiler pass (`mir_cancel_edges.c`, not switched on) and `ms_sched_cancel_return()` (no callers) but wrote the natives with jumps.

## Design

1. **A cancelled wait is a status.** `abi/status.h` gains `MS_STATUS_CANCELLED`. `ms_net_finish` and `ms_fail_finish_at` return it instead of jumping; so do the pool waits in `fs_job.c` and the terminal reads. Core waits answer `MS_WAITER_CANCELLED` (`promise.h`), since their answers are promise outcomes and indexes, not statuses.
2. **Every frame returns.** A caller treats the status as it treats `MS_STATUS_TIMED_OUT` or `MS_STATUS_CLOSED`: free, close, return it. No new path is written; the error path already exists and already runs in tests.
3. **One place ends the call.** Compiled code receives every `T!` native's failing status in `msstd_status_error` (`stdlib/core/core.ms`), which lowering already calls for every such extern. It ends the task there (`msrt_cancelled`), holding nothing of the runtime's. The few entries that wait and return no status (`msrt_promise_wait`, `msrt_group_next`, `msrt_pipe_try`) call `ms_sched_cancel_return()` themselves.
4. **C tasks see it too.** The server's connection loop and writer get the status from their read or write and return; their guard sees an ordinary return. A handler closure they call is compiled code under its own guard, as now.
5. **Lint.** Under the directories listed in `NO_UNWIND` (`src/lint/rules.c`), `ms_cancelled()` is allowed only in `unwind.c`, `fault_abi.c` and `start.c`, and `ms_sched_cancel_return()` only inside a function named `msrt_*` or `msstd_*`. Stage 1 lists `runtime/core` and `runtime/entry`; stage 2 adds the rest of `runtime`.
6. **Registrations go away.** Once a directory is under the rule, its `ms_cleanup_push` calls that exist only for cancel are deleted (most of the 19 in `runtime/std`; each is checked when its file is converted). Those that guard a call into compiled code, which can still fault, stay.

When the back end turns cancel edges on, `ms_sched_cancel_return()` and the status path already deliver by returning, so nothing here changes.

## Stages

1. Core waits return `MS_WAITER_CANCELLED`; `msrt_` entries end the call; the lint rule. No behavior change.
2. The status and its one ending place; net, TLS, DNS, HTTP server and client, files, terminal converted; their cancel registrations deleted; `NO_UNWIND` covers `src/runtime/`. #6774 closes with it.

## Alternatives considered

- **Do nothing, keep registering.** Works site by site. The table above is the cost: four rounds of leaks, each found late.
- **A per-task list of owned blocks, freed at teardown.** One call at each allocation instead of two around each wait. Still a remembered call per site, and it duplicates the cleanup stack the task header already has.
- **A scope helper (`ms_scoped`).** Harder to misuse than push and discard, same exposure: a site that does not use it leaks.
- **Free everything a task allocated when it ends.** Values move between tasks through pipes and promise results, so the allocator cannot know the owner.
- **Turn cancel edges on first.** They make compiled code return too, which is separate from this rule and is the back end's change; this rule does not need it and is ready for it.

## Testing

- `ms_lint` fails on a planted `ms_cancelled()` in core and on `ms_sched_cancel_return()` in a helper.
- `tools/cancel-sweep.ms` on the promise, pipe, HTTP and TLS fixtures: no leaking run, at one thread and the default.
- `tools/leak-check.ms`, `ctest`, `conform`.
