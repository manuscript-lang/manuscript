[Wiki](../index.md) › [Runtime](index.md)

# The C runtime takes idle HTTP connections by claiming their finished read

Verified (2026-11-23): a handler that computes holds its thread, and a connection task parked in a read there cannot run even after its bytes arrived. The C port moves the connection, not the task. A connection that waits for the first byte of a request lists itself (`http_serve_steal.c`); the watcher hook (`core/watch.h`) finds a thread that stopped turning and mails `MS_MAIL_IDLE` to a resting thread of the same server, whose take task claims every listed read that has finished (`ms_net_core_steal_read` in `net_conn.c`: the bytes move out of the read operation, its waiter gets CLOSED) and serves the socket in a connection task of its own. The old task ends without closing the socket (`conn->taken`).

- A read that has not finished stays put; only finished reads move, so a take never loses bytes.
- The request task is spawned `MS_SPAWN_FRONT`, so a request runs before the other ready connections are read. Without it the pair connection's request was already consumed when the long handler began, and nothing could be taken (the fixture failed one run in five).
- `Placement.Spread` must place each promise on a different thread (`ms_workers_spread_pick`, with the task count each isolate reports). Before, all three workers ran on one thread and there was nothing to take it to.
- Not taken yet: TLS and HTTP/2 connections (their session lives in the task or the secure transport); an empty take backs off two milliseconds.

Apply when: changing the HTTP connection loop, `ms_net_read`, the watcher hooks or spread placement.
Evidence: [http_serve_steal.c](../../src/runtime/std/http_serve_steal.c), [net_conn.c](../../src/runtime/std/net_conn.c), [Rust-era design](a-computing-handler-holds-its-thread-so-idle-connections-are-taken.md).
Verify: fixture `e2e/stdlib/http-long-handler-does-not-hold-others` passes 30 runs in 30.
