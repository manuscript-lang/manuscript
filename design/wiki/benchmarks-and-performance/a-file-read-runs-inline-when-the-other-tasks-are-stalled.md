# A file read runs inline when every other task is stalled

`ms_fs_run` handed each file job to libuv's pool unless the isolate had one task. In `pargroup` (2000 small files, `map_concurrent` over 4 workers) a worker has the running task plus tasks parked on remote waits, so every `read_file` cost two thread wake-ups: about 6 futex, 1.5 epoll and 1.5 eventfd writes per file, and four workers were slower than one (50 ms against 39 ms; Rust 28 to 33 ms).

`pool_alone()` in `pool.c` already treats "the others are stalled on remote waits" as alone (`ms_task_others_stalled`); `ms_fs_run` now uses the same test. Nothing else can run on that thread while it blocks, so blocking costs nothing. Measured: `pargroup` 41-50 ms to 17-21 ms (min of 9); callgrind -2.6%; `treegrep` unchanged.

A rule for runtime waits: use `ms_task_others_stalled` where a blocking call can run inline, not the bare task count.
