# HTTP server: cheaper request task lifecycle (promise-free request tasks)

## Summary

- Each `/health` request creates a promise and a task and tears both down: about 1,750 to 2,000 of 12,695 instructions (14 to 16%).
- Worker tasks that are recycled would save about 1,150 net but add cancellation state that is easy to get wrong. A plain, promise-free, self-freeing request task saves about 900 with no new state.
- Decision: build the promise-free task; do not build workers.

## Status

Implemented, 2026-11-12 (promise-free variant), against `478c8c89`. Independent review: worker recycling rejected, numbers corrected, promise-free variant added. Measured 12,695 to 11,780 instructions per `/health` request (−7.2%). Direction (Chinmay): bring the single-core server to hyper level; inline handlers on the connection task were rejected as unsound for cancellation and timeouts.

## Problem

Measured: callgrind, `bench/perf/web/ms` `/health`, 49,576 requests, exact call counts, `9f95b521`.

| Per request | Instructions |
| --- | ---: |
| `start_native` (closure, `msrt_promise_new` 197, `start_on` 522 incl. `msrt_task_spawn` 268 and 90 of `apply`) | 754 |
| `msrt_promise_drop` | 144 |
| `free_task` | 138 |
| `task_ended` (281 of `apply`, `msrt_shield_exit` 57) | 412 |
| outer `msrt_guard_call` 102, `task_main` 90, `hibernate_idle` 38 | 230 |
| `server.tasks` insert and remove (`server.rs:409`) | 126 |
| `swap_ctx` (about 2.25 calls) | 302 |

- Rows are non-overlapping except where noted; the sum is about 1,750 to 2,000.
- Hyper serves the request in 6,733. Parse, handler and send together cost about 8,100 (`request_task` 6,621 includes `send` 1,439), so removing the whole lifecycle still leaves about 10,700.

## Design

- The server does not use the promise: cancel on disconnect goes through `rt::cancel_task` (`server.rs:1141`), the deadline through `limit_current_until`, which already resets per request (`exchange.rs:123`), and close can cancel through `server.tasks`.
- Add a spawn flag, contained and self-freeing, to `msrt_task_spawn` (`task/api.rs`, `task_main` at 94-132). A flagged task needs no promise, no `apply` events, no `msrt_promise_drop`, and no sweep; its fault is reported by its own guard.
- `start_native` keeps its promise for other callers; the HTTP server moves to the new spawn.
- Each request still gets a fresh task, so there is no state to reset between requests.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt` `task/api.rs`, `promise.rs` | promise-free contained spawn | task unit test: fault, cancel and free without a promise |
| `ms-std-net` `http/server.rs`, `rt.rs` | spawn request tasks with it; delete `sweep_handlers` and the promise bookkeeping | `http-parked-pipeline.ms`, timeout-cancel and disconnect-cancel fixtures, leak check |

## Alternatives

- Do nothing: 14 to 16% of instructions stay.
- Recycled worker tasks: about 1,150 net after queue, wake and reset. A cancel or kill deadline landing between requests would cancel the next request or the idle worker; shield depth must be restored; a fault outside the handler guard ends the worker. `swap_ctx` and the guard stay. Rejected: more saving than the chosen design (about 250) at the price of that state.
- Cache the promise slot: the slot is already on a free list (`promise.rs:390`); the cost is resetting 17 per-slot vectors (`promise.rs:414-430`), so little is saved.
- Inline handlers: rejected as unsound.
