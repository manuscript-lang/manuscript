[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A busy queue must not poll descriptors on every task switch

Verified (2026-11-12, `bench/perf/web`, one thread, 64 keep-alive connections): `switch_away` ran `epoll_wait(0)` at every switch while a task waited on a descriptor, so a server ran one `epoll_wait` per request (16.9k for 16.2k requests under `strace -c`; a C epoll server needs 393 for 25k). It now polls every `POLL_EVERY` (32) switches, and the idle path still blocks in `reactor_wait`. System time per `/health` request fell from 4.4-4.8 to 4.0-4.4 µs, matching C's 4.1-4.4.

Also learned: a `gdb`/`ptrace` stack sampler lands in `send` and `recv` for any loopback server (the process is stopped inside the syscall), so it cannot find user-time costs; compare `utime` and `stime` per request from `/proc/<pid>/stat` instead, then profile with callgrind and a small allocator reservation. Two server threads on a four-CPU VM saturate the Go load generator (about 185k req/s), so compare servers on one CPU.

Apply when: changing the scheduler's polling policy or reporting server throughput.
