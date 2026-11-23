[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A lone task runs file calls in place

Verified (2026-11-23, `bench/perf/suite/treegrep`, 2000 small files): every `@std/os/fs` call handed its job to the blocking pool and parked, so a file read cost about 50 us of thread wake-ups (13.5k `futex`, 4k `epoll_pwait` and 4k eventfd `write` calls for 2000 files), 100 ms in all against 20 ms for Rust. `ms_fs_run` now runs the job on the calling thread when `ms_task_count() <= 1`, since nothing else can run while the call blocks: 100 to 40 ms, and the remaining syscalls are the `open`, `read`, `statx` and `close` the work needs.

Apply when: a loop of small file operations in a program with one task is several times slower than Go or Rust. A program with other tasks still uses the pool, so a slow file does not stall them.
Verify: `strace -f -c ./program` shows no `futex` or `epoll_pwait` per file.
