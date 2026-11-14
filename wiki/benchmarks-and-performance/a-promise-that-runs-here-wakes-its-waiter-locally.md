[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A promise that runs here wakes its waiter locally

Verified (2026-11-14, `bench/perf/suite/treegrep`): `read_file(p).wait()` made the waiter's token remote because any started promise might finish on another thread, so `pool::alone()` was false and every small file read went through the blocking pool (2 futex, an epoll_wait and an eventfd write per file; 90 ms against C's 27). Promises started with `Placement.Here` carry the `HERE` flag and park on a local token, so a lone task reads inline (33 ms).

Apply when: changing promise placement, `park_on`, or `msrt_task_others_stalled`. Check `strace -c -f` for futex and epoll_wait counts in a loop of `read_file(..).wait()`.
