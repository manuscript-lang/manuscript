# HTTP server: one scope task per request

## Summary

- The server runs each request as a task of a server-owned runtime scope (the primitive behind `TaskGroup`, contained faults), not inline on the reactor task.
- Deletes the reactor-role handoff: `PARKING`, `give_up_reactor_role`, the role check in `run_handlers`, the `handlers` registry, and the runtime-wide `msrt_task_set_prepark` hook that only this code uses.
- Gives each request the standard lifetime tools: a runtime kill deadline (`server timeout`), cancel on client disconnect (absorbs #1341), cancel on server close after grace.
- Cost measured by a spike: within noise once the task stack pool exceeds one reactor batch; 3.4x slower with the current pool of 32. Re-measured on the real mechanism in each stage.
- User-visible: an overdue buffered handler is cancelled at the deadline instead of finishing and then being answered 504 (same response, earlier). Streaming and WebSocket exchanges keep their own deadlines.

## Status

Implemented, 2026-10-26 (#1349, #1351, #1353, #1354). Proposed 2026-10-25 against `a3e9e41a`. Direction (Chinmay, 2026-10-25): "move to the concurrency model? use task group at the very least and get rid of this custom stuff". Builds on `proposals/taskgroup.md` and `proposals/taskgroup-request-scopes.md` (contained faults #1327, `tasks.cancelled()` #1333).

## Problem

- `crates/ms-std-net/src/http/server.rs` runs handlers inline on the reactor task (`run_handlers` → `dispatch_conn`; same in `h2serve.rs` `h2_buffered`/`run_streaming` and `exchange.rs` `run`). A handler that parks would stall all I/O, so a global prepark hook (`rt::install_prepark_hook`, `msrt_task_set_prepark`) makes the first park of the reactor-hosting task spawn a replacement reactor task and drop the role. `PARKING` exists to tell the reactor's own park apart from a handler's.
- This is a bespoke scheduler inside the server: three thread-local states (`role`, `PARKING`, `handlers`) and a runtime hook that every task park pays for.
- The request has no lifetime of its own. `limits.timeout` is checked after the handler returns (`late`); a handler that never parks cannot be stopped, and one that does park is never cancelled by the deadline or by the client leaving (#1341). `sweep_timeouts` skips `Phase::Busy`.
- Non-goals: exposing the server's group to user code; changing `serve` options; worker threads; stopping a handler that never waits (the kill timer runs only when the scheduler runs, `task.rs` `expire_kills`; such a handler polls `tasks.cancelled()`).

## Design

- `Server` creates a runtime scope with contained faults (`msrt_scope_new` + `msrt_scope_contain`, what `TaskGroup(contain_faults: True)` wraps) on the first `serve`, and closes it in `close_inner`.
- `run_handlers` no longer calls `dispatch_conn`. For each ready connection it spawns a task in the server's scope whose body is today's `dispatch_conn` (h1 buffered, h1 streaming, and one h2 stream per call, since `h2_dispatch` already takes one stream). The reactor task only does I/O and timers and always owns the role.
- Spawn: new `scope::spawn_native(scope, entry, arg, limit_ns)` in `ms-rt`: a Rust entry with the default stack size (`stack_bytes` 0, so the pool applies; `TASK_GROUP_STACK` is not pooled) and no `capture_frames`. The task is self-collecting: when it ends it leaves the scope's list and its record is freed, so a long-lived server does not accumulate one finished task per request (`msrt_scope_spawn` tasks stay until joined). Scope close still cancels and joins the live ones. `limit_ns` is the server timeout, so the runtime's existing kill timer cancels an overdue request; the guard reports `Outcome::Cancelled`, which already maps to 504. The post-hoc `late` check goes away.
- Disconnect (PR 3): `detach` currently sets interest to none, so no hangup event reaches a busy connection. For buffered h1 requests (the body is already read) keep `Ev::HUP`-class interest while `Busy`, and on EOF/reset call `msrt_task_cancel(handle)` with the handle stored in `Phase::Busy`. Streaming exchanges read the connection themselves (`exchange.rs`), so they are cancelled by their existing socket errors, not by this reader. h2 already wakes handlers on connection close (`wake_waiters`).
- Shield: `DrainShield` shields one task. Each request task enters `rt::shield()` for its duration when the server drains on stop (`grace` nonzero, `Reactor::drains`), so SIGINT/SIGTERM still lets in-flight requests finish within grace (`stdlib/http.ms` contract) instead of waking parked handlers with `WAIT_CANCELLED`.
- Close and drain: `close_inner` waits for the scope within `grace`, then `scope::close` cancels what remains. `drained()` keeps counting connections; the `handlers` vector is replaced by "is the current task in this server's scope" for `CloseError::FromHandler` and `in_handler_of_network`.
- Faults: unchanged. `guarded` (`msrt_guard_call`) still turns a handler fault into 500; the scope is contained, so a stray task fault cannot end the process either. Frame-owned values still leak on faults (#1325, owned by "Harden the HTTP server"; this change adds no new leak and reuses whatever fix lands there).
- Stack pool: `STACK_POOL` in `ms-rt/src/task.rs` rises from 32 to 512 (pooled stacks are only those a burst already created; peak concurrency already reserved that address space, and nothing is released now that was not before at the 32 mark). The reactor spawns every ready request in a batch (up to 64 per `poll`) before any runs, so a pool of 32 overflows each batch and every task pays `mmap`+`mprotect`+two `munmap`.

## Evidence

Spike: `run_handlers` spawned `rt::spawn_detached` tasks running `dispatch_conn`; nothing else changed. `bench/perf/web` `/health`, `/user/42`, `/top?n=10`, 64 connections, 4 s, three rounds, server on CPUs 0-1, load on 2-3, 4-CPU shared Linux VM (+/-10% run to run).

| Build | `/health` req/s | `/user/42` req/s | `/top?n=10` req/s |
| --- | ---: | ---: | ---: |
| main `a3e9e41a` | 104.0k–111.1k | 100.2k–113.0k | 23.2k–25.0k |
| spawn per request, pool 32 | 31.9k–32.8k | 31.8k–32.9k | 15.4k–17.3k |
| spawn per request, pool 512 | 101.1k–113.5k | 93.5k–100.6k | 23.3k–24.3k |

`strace -c` on the pool-32 run: per request 1 `munmap`, 0.5 `mmap`, 0.5 `mprotect` (stack creation trimming the aligned slot, `task.rs` `stack::create`). Gone with pool 512. The earlier review's warning (per-request spawn costs) is right for the current pool and wrong once stacks are reused; context switch and task record are not measurable at this rate.

Code removed: about 90 lines in `server.rs` (role, `PARKING`, `give_up_reactor_role`, `handlers`, `enter_handler`/`leave_handler`) and their four call sites; `install_prepark_hook` and `msrt_task_set_prepark` with the `PREPARK` check in `task.rs`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt` `scope.rs`, `task.rs` | `spawn_native`; pool 512; remove prepark hook | scope unit test: native spawn honors limit and close |
| `ms-std-net` `http/server.rs` | scope, spawn per request, delete handoff, cancel on disconnect, drain via scope | existing `handlers_run_concurrently`, `http-parked-pipeline.ms` (unchanged), new disconnect-cancel and timeout-cancel fixtures |
| `http/server/h2serve.rs`, `http/exchange.rs` | drop `enter_handler`/`leave_handler`; dispatch bodies run in the task | existing h2 and exchange tests |
| `ffi/net.rs` | `in_handler_of_network` via scope membership | existing close-from-handler fixture |
| `stdlib/*.ms`, docs | `Network.serve` docs: timeout now cancels the handler; disconnect cancels it | docs build |
| Compiler, formatter, LSP | unchanged | |

## Alternatives

- Do nothing: keeps the bespoke role handoff and no request cancellation. Rejected by direction.
- Keep inline execution as a fast path and spawn only when a handler parks: needs the prepark hook, i.e. today's mechanism.
- Fixed worker tasks pulling from a queue: a second scheduler; the runtime already schedules tasks.
- Per-request Manuscript `TaskGroup`: the server is Rust and the group is the same scope primitive; a handler can still open its own group inside its request task.

## Staging and verification

1. PR 1, `ms-rt`: `spawn_native`, pool 512, tests. Gate: `bench/perf/web` unchanged with the spike patch.
2. PR 2, server: dispatch via scope tasks for h1 buffered, streaming and h2; delete the handoff and the prepark hook; drain through the scope. Gate: `make verify`, full `cicd.yml` dispatched on the branch (PRs run Linux only), web bench within noise of main, `http-parked-pipeline.ms` unmodified.
3. PR 3, #1341: kill deadline on the request task, cancel on disconnect, docs, fixtures.
4. Add a dated section to `bench/perf/web/results.md` with each measurement.

Risks:

- Windows: `stack::POOLED` is false for fibers, so every request creates and destroys a fiber. Not measured here; PR 2 gates on the CI numbers and pools fibers if they regress.
- Interleaving: tasks switch only at parks, as before; no `RefCell` borrow may live across a park, already required of handlers under the handoff.
- Memory: pooled stacks keep the pages their tasks touched and reserve 256 MiB of address space each. PR 1 records resident memory after the web bench (main was 70 MB) and adds `madvise` on release if a deep stack stays resident.
- Kill timer cannot stop a handler that never reaches the scheduler; unchanged from today, stated as a non-goal.
- Overlap with #1325: the leak fix touches `guarded`; PR 2 does not change it.

## Open questions

None needing the owner.

## Review

Skeptic review (2026-10-25) returned REVISE: SIGINT drain shield, uncollected finished tasks, disconnect interest while busy, unpooled stack size in `spawn_closure`, memory claim, and streaming deadlines were missing or wrong. Each is now in Design or Risks; the spike used `spawn_detached`, so PR 1 and PR 2 re-measure on the real mechanism before merging.
