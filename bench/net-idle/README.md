# Idle connection memory of the C network path

`server.c` serves HTTP keep-alive ("hello") and echoes WebSocket frames using only C runtime pieces: `src/runtime/sys` sockets, one libuv poll handle per connection, the `src/runtime/io` completion ring and shared scratch read buffer, 64-byte connection rows, and the llhttp and WebSocket parsers of `src/runtime/net`. `client.py` opens N idle connections and reads the server's `VmRSS` and `VmPTE` before and after. `run.sh` builds and runs it (Linux; `ulimit -n 20000`).

A connection costs one 64-byte row plus one 160-byte `uv_poll_t`, nothing else while idle: no read buffer, no stash, no task stack. Kernel socket memory (about a few KB per TCP socket in slab) is not in the server's RSS.

## Results

2026-11-20, runtime at the merge of PR 4672, 4 vCPU x86-64 cloud VM, plain TCP, libuv 1.48 (system package).

| Mode | Connections | RSS per idle connection | Page table |
| --- | --- | --- | --- |
| WebSocket | 2000 | 195 B | 0 |
| WebSocket | 8000 | 264 B | 0 |
| HTTP keep-alive | 2000 | 195 B | 0 |
| HTTP keep-alive | 8000 | 264 B | 0 |
| WebSocket over TLS | 2000 | 17,926 B | 35 B |
| WebSocket over TLS | 8000 | 17,994 B | 35 B |
| HTTP keep-alive over TLS | 2000 | 17,926 B | 35 B |
| HTTP keep-alive over TLS | 8000 | 17,994 B | 34 B |

The target is under 1 KB of native state per idle connection. Plain TCP meets it by 4x. The Rust server this replaces holds an idle WebSocket at 6.6 KB resident plus 1.0 KB of page tables, and an idle rustls connection at 8.1 KB (`/mnt/project-files/c-backend/baselines-2026-11-20.md`).

**TLS misses the target and is worse than rustls.** An idle OpenSSL server connection costs about 18 KB even with `SSL_MODE_RELEASE_BUFFERS`, tickets, session cache and compression off. `tls_memory.c` shows `SSL_new` alone is 9.4 KB (the `SSL`, its certificate state and the two memory BIOs) and the finished handshake brings it to 17.2 KB (session, traffic secrets, two cipher contexts). Neither is released while the `SSL` lives, so no setting of the `SSL` object gets near 1 KB.

Limits of the probe: one thread, the TLS server certificate is a throwaway ECDSA P-256 one,  a WebSocket frame split across reads closes the connection, no pipelined HTTP requests. The numbers are bytes of state, not throughput.
