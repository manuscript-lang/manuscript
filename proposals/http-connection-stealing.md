# Idle HTTP connections move off a held-up thread

## Summary

- Problem: a handler that computes stops its thread's reactor, so every request on that thread's other connections waits; p99 rose to the handler time, 2 to 3 times Go's.
- Change: a server lists its connections that wait for a request; a watcher thread finds a thread that stopped turning, and a resting thread of the same `serve` call takes the listed connections that have a request.
- Decision requested: none; no API, language, or default changes. Implemented in the same PR.

## Status

Implemented, 2026-11-16, on `claude/project-thread-cuchaa`. Owner direction (2026-11-15): "no marker, this is an internal detail"; "it needs to be better across the board"; "elegant, simple and highly efficient". Two earlier designs were rejected by skeptical review and by measurement (see Alternatives); the owner then asked for no further subagent review, so this design stands on the measurements below.

## Problem

`bench/perf/http-tail`, 4 vCPU VM, open loop, 64 connections, 2000 req/s, every 20th request burns 5 ms (measured, `main` at 688af5b7):

| Server | p50 | p99 | p99.9 |
| --- | --- | --- | --- |
| Manuscript before | 0.75 to 0.84 ms | 5.8 to 6.2 ms | 9.1 to 18.7 ms |
| Go | 0.65 ms | 2.9 to 3.2 ms | 5.7 ms |
| Node | 2.5 ms | 10.8 to 15.9 ms | 16.7 to 28.4 ms |

- A task is never interrupted and a started task never moves (`crates/ms-rt/src/sched.rs`), so the wait cannot be fixed by moving the handler.
- Fast handlers already matched Go, so the fast path must not pay: CPU, memory, p50 and throughput stay at or better than before.

## Design

One rule: between requests a plain HTTP/1 connection is only a socket and a deadline, so it can change threads; nothing else moves.

- `steal::Member` (one per server, `crates/ms-std-net/src/http/server/steal.rs`): a locked flat list of `(token, socket, deadline, taken)` for connections in `Phase::Head` with nothing buffered. Listing and unlisting are one uncontended lock each per request.
- `ms_rt::watch` (`crates/ms-rt/src/watch.rs`): one thread that looks every 2 ms, every 100 µs for 0.1 s after a hook asks, and sleeps when every scheduler thread has rested for 20 looks. It reads atomics only and calls registered hooks.
- Held up: the thread is not resting, and both its reactor's last turn and its last wake-up are older than the watcher's previous look (`Beat::held_up`). The wake-up stamp matters: without it a thread that just woke looks held up and the watcher never slows down (measured: +40% CPU at 4000 req/s).
- The HTTP hook asks for frequent looks only after it helped a thread held up for 1 ms or more. Shorter stalls (a thread the OS set aside) are helped at the slow rate; chasing them cost 7% throughput at full load (measured).
- Taking: the HTTP hook orders a resting server of the same `serve` call to take from the held-up one. The taker polls the listed sockets with a zero timeout, duplicates the ready ones under the list's lock, marks them taken, and serves them as new connections with the old deadline.
- Dropping: the owner finds its entry marked taken the next time it touches the connection or turns, and closes its handle without a shutdown. The lock orders "owner uses" against "taker duplicates", so exactly one thread reads a request.
- The reactor runs a started request before it reads the next ready connection, so connections behind a long handler are still unread and can be taken.
- Balance: every 10 ms the server with the fewest connections takes half its difference to the one with the most (a take moves every ready connection, which can pile them on one thread; measured throughput 93k without, 117k with, 117k before).
- Not listed: WebSocket connections, HTTP/2 connections with an open stream, and connections with a request in progress. Idle TLS and HTTP/2 connections are listed with their session and stream table, which the taker continues (added after the first version).
- Platforms: `poll`/`dup` on Unix, `WSAPoll`/`WSADuplicateSocket` on Windows (`sys::readable`, `sys::duplicate`); same behavior on all three.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt` `watch.rs`, `sched.rs` | watcher thread, hooks, resting mask, wake-up stamp | `a_hook_is_added_once_and_runs_while_the_watcher_is_awake` |
| `crates/ms-std-net` `http/server/steal.rs` | lists, take, balance, hook | `unparking_moves_the_last_entry_into_the_place`, `taking_ready_connections_leaves_the_quiet_ones`, `balancing_moves_half_the_difference` |
| `crates/ms-std-net` `http/server.rs` | list on idle, unlist on use, forget a taken connection, reactor yields between requests | fixture `e2e/stdlib/http-long-handler-does-not-hold-others` (fails without the change) |
| `crates/ms-std-net` `sys/unix.rs`, `sys/windows.rs` | `readable`, `duplicate`, `Poller::waker` | the two tests above; Windows and macOS CI on the branch |
| `bench/perf/http-tail` | new suite with Go and Node ports | dated results in its README |

## Results

Same machine, alternated runs (measured, 7d462817 plus this change; full table in `bench/perf/http-tail/README.md`):

| | Before | Now | Go |
| --- | --- | --- | --- |
| 5% slow requests: p50 / p99 / p99.9 | 0.8 / 6.0 / 9 to 19 ms | 0.63 / 3.2 / 5.6 ms | 0.65 / 3.0 / 5.7 ms |
| Fast handlers: p50 / p99 | 0.67 / 1.8 ms | 0.67 / 1.5 to 1.9 ms | 0.66 / 1.8 ms |
| CPU for 88,000 fast requests | 5.2 to 5.8 s | 5.4 to 6.0 s | 9.6 to 10.1 s |
| Peak memory | 7.5 MB | 6.4 MB | 14.5 MB |
| Closed loop | 118k to 121k req/s | 112k to 113k req/s | 53k to 56k req/s |

- Known cost: an OS-descheduled thread looks held up, so connections may move that needed no help. A single 1 ms interval was measured and rejected for its slow-mix p50 and p90 (wiki, 2026-11-16).

## Alternatives

- Do nothing: p99 stays at the handler time whenever any handler computes; the owner named HTTP serving the first use case.
- Run handlers on other threads from the stdlib (built, measured, reverted): +75% CPU, p50 +0.2 ms, throughput 85 to 106k against 140k, because every request crossed threads twice.
- One poller shared by all threads (reviewed, rejected): connection state, tasks and native streams are thread-bound, and Windows has no equivalent.
- Interrupt the computing task, as Go does with a signal: needs safe points in compiled code on three platforms; not needed once connections can move.
- Fire a running task's time limit from the watcher (built, removed): the cancellation points that matter already enter the scheduler, which fires it; pure loops need back-edge checks, which the owner declined (2026-11-15).
