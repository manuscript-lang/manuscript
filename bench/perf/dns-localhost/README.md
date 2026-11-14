# `lookup("localhost")`

`main.ms` and `main.rs` resolve `localhost` 20,000 times and print ns per call (`ms run bench/perf/dns-localhost/main.ms`; Rust: `ToSocketAddrs`).

## 2026-11-14 (x86-64 Linux sandbox, 4 cores, release `ms`, base 2bae6108)

`localhost` and `*.localhost` are loopback by RFC 6761, but the lookup still handed the name to a blocking-pool thread to find that out: a task switch and two wake-ups for a constant. It is now answered before the hand-off.

| | per call |
| --- | --- |
| before | 31 us (30.6 to 31.7) |
| after | 0.39 us |
| Rust `to_socket_addrs` | 2.8 us |

Other names still use the pool.
