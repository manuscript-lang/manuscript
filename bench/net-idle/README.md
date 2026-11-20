# Idle connection memory of the C network path

`server.c` serves HTTP keep-alive ("hello") and echoes WebSocket frames using only C runtime pieces: `runtime/sys` sockets, one libuv poll handle per connection, the `runtime/io` completion ring and shared scratch read buffer, 64-byte connection rows, and the llhttp and WebSocket parsers of `runtime/net`. `client.py` opens N idle connections and reads the server's `VmRSS` and `VmPTE` before and after. `run.sh` builds and runs it (Linux; `ulimit -n 20000`).

A connection costs one 64-byte row plus one 160-byte `uv_poll_t`, nothing else while idle: no read buffer, no stash, no task stack. Kernel socket memory (about a few KB per TCP socket in slab) is not in the server's RSS.

## Results

2026-11-20, runtime at the merge of PR 4672, 4 vCPU x86-64 cloud VM, plain TCP, libuv 1.48 (system package).

| Mode | Connections | RSS per idle connection | Page table |
| --- | --- | --- | --- |
| WebSocket | 2000 | 195 B | 0 |
| WebSocket | 8000 | 264 B | 0 |
| HTTP keep-alive | 2000 | 195 B | 0 |
| HTTP keep-alive | 8000 | 264 B | 0 |

The target is under 1 KB of native state per idle connection; the Rust server this replaces holds an idle WebSocket at 6.6 KB resident plus 1.0 KB of page tables (`/mnt/project-files/c-backend/baselines-2026-11-20.md`, 1 thread, 2k to 10k connections). TLS adds an OpenSSL `SSL` (about 18 KB with `SSL_MODE_RELEASE_BUFFERS`; see `/mnt/project-files/c-backend/net-measurements.md`), so a TLS number belongs to the TLS stage, not here.

Limits of the probe: one thread, a WebSocket frame split across reads closes the connection, no pipelined HTTP requests. The numbers are bytes of state, not throughput.
