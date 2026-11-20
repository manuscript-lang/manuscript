# Net natives on the C connection rows

## Summary

- Problem: `ms-std-net` is 30k lines of Rust with 83 natives; the C units in `runtime/net` (conn, http1, tls, ws, h2) are socket-free and not reachable from any program.
- Change: a small set of socket natives in C over the existing rows, with Network policy, DNS choice, routing, header rules and the HTTP/WebSocket server loop in stdlib `.ms`. `ms-std-net` is deleted when nothing is left in it.
- Decision requested: the object model and native list below, which the client/DNS, h2 and policy threads build on.

## Status

Proposal, 2026-11-20, checked against `bbfa1032`. Chinmay: "leverage the dependencies as much as possible, dont reinvent things"; "dont port over rust idiosyncrasies, do them in c first fashion". Nothing implemented.

## Problem

- Verified: `crates/ms-std-net/src` is 30,072 lines; `rt_symbols.txt` lists 83 `msstd_net_*`, `msstd_http_*` and `msstd_ws_*` natives, none defined in C.
- Verified (`conn.rs`, `net.rs`, `http/server.rs`): Rust keeps `Rc<Connection>` with shared ends, an `Arc<Network>` that owns every resource and enforces host and CIDR policy, and a reactor task per server with its own readiness set and work stealing. These are Rust shapes, not requirements.
- Verified (`runtime/net/conn.h`): the C row is 64 bytes, handles carry a generation, stale handles resolve to NULL.
- Measured target (`threads.md` W6): under 1 KB of native state per idle connection.

## Design

Layers, bottom up. Each layer has one owner thread.

1. Sockets (`runtime/sys`, exists): `ms_sys_net_*` for socket, bind, listen, accept, connect, shutdown, addresses.
2. Waiting: a native parks the task with `msrt_task_wait_fd` (already C) and then makes the nonblocking call. No second readiness set; the server needs no reactor task of its own.
3. Connection object (this proposal): one `MsObj` per `ConnH` holding the row id from `MsConnTable`, a count of ends (`share`, `alias`, `close_if_last` keep their meaning), and the TLS state in `row->ext` (`runtime/net/tls.c`, memory BIOs). Read and write go through one function pair that handles plain and TLS the same way.
4. Listener object: the descriptors, the bound address text, closed flag. `accept` parks on the descriptor; `accept_raw` returns the descriptor number for a worker thread to adopt.
5. Raw natives (the only net natives left in C): `listen(sockaddr)`, `connect(sockaddr, timeout)`, `accept`, `read`, `write`, `shutdown_write`, `close`, `share`, `local_address`, `peer_address`, `start_tls`, `accept_tls`, `tls_info`, datagram bind, receive and send. They take already-checked, already-resolved addresses.
6. Policy in `.ms` (policy thread): `Network` as a Manuscript record holding host rules, CIDRs, `allow_listen` and the resolver; `restrict`, `with_resolver`, `lookup`, `resolve`, IP and CIDR parsing and text. Resolution calls the client/DNS thread's `uv_getaddrinfo` native.
7. HTTP/1 server in `.ms`: accept loop, a task per connection, request head from `ms_conn_h1_feed` (llhttp), body framing, `Exchange`, headers, WebSocket upgrade. C supplies parsing and frame codecs only.

Error texts and status codes stay what stdlib users see today; the conformance corpus is the check.

Cancellation: every park returns on cancel, closes nothing itself; `close` is the only call that frees a row. A write that cannot finish keeps its bytes in the row's `wpend`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `runtime/net/conn_object.c`, `listener.c` | new: objects and raw natives | `runtime/tests/net_conn_test.c` (loopback, TLS, stale handle, cancel) |
| `runtime/include/ms_rt/net.h`, `symbols/net.txt` | the raw native list with `ms-sig` | `cargo xtask symbols --check` |
| `stdlib/net/*.ms`, `stdlib/http/*.ms` | policy and server loop | conformance net fixtures |
| `crates/ms-std-net` | deleted last, in the policy thread's PR | corpus on six platforms |

## Alternatives

- Port `Connection`, `Network` and the server reactor 1:1 into C: keeps Rust's shared-ownership shapes and a second readiness set; rejected.
- Keep Rust until every part is ready: leaves 30k lines and blocks the no-Rust goal; rejected.
- Park on the reactor ring (`ms_io_ring`) instead of `msrt_task_wait_fd`: the ring is not wired into the reactor yet and wait_fd already serves files and pipes; revisit if the idle-connection measurement misses 1 KB.
- Do nothing: no C net path.

## Open questions

- Does `msrt_task_wait_fd` park cheaply enough for 100k idle connections? Measure with `bench/net-idle` before the server loop moves.
- Worker model for `accept_raw` (threads versus one task per connection): decide with the h2 thread.
