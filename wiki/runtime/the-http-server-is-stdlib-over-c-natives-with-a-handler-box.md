[Wiki](../index.md) › [Runtime](index.md)

# The HTTP server is `stdlib/net/serve.ms` over C natives, with a handler box

Verified 2026-11-20 (the Rust `serve`, h2 and exchange were deleted): `serve` starts an accept loop promise; each connection is a `Placement.Spread` promise that adopts the socket (`msstd_conn_share`), does TLS (`msstd_conn_accept_tls_with` on a context built once by `msstd_tls_server_new`) and picks h1 or h2 from ALPN. Requests run through `msstd_xchg_*` and `msstd_h2_*`.

- The user's handler is a closure, which has one owner and cannot cross threads. `runtime/net/handler.c` boxes it (refcounted, atomic) so every thread calls it: `msstd_handler_call` sets a thread-local slot and runs the stdlib `serve_one` closure, which calls `msstd_handler_take()` first and `msstd_handler_keep(Bool)` before it returns.
- Every native with an `err` slot calls `ms_net_clear_text(err)` first: the caller reads the slot for any failure status, and an uninitialized slot segfaulted `status_error`.
- A result written through `out` must be named `out` in its `ms-sig`, or lowering fails with "missing argument".
- Closing is graceful because `HttpServer.close()` fires a `Cancel` (`stopping`), the accept loop returns normally and `Accepting.close` drains. A cancelled frame instead ends the promises it started before any cleanup runs, so connections die first; a drain on cancel needs a runtime option, not a cleanup.
- Peer-gone detection: h1 `ms_conn_wait_gone` waits readable then peeks (EOF or half-close is gone; pipelined bytes are not); h2 wakes the stream's watcher token on RST_STREAM. The request promise is cancelled through its `Cancel` switch; the deadline is the promise `timeout` (ETIMEDOUT answers 504).
- `run_unstarted` must clear `queued` when the waiter runs a promise inline, or a cancelled frame joins the promise it is running in (a SIGTERM hang).
