[Wiki](../index.md) › [Runtime](index.md)

# The libuv reactor refuses files and named pipes, and runs on every Unix target

Verified (macOS CI, 2026-11-20): `uv_poll_init` returns EINVAL for regular files and directories on every platform, and on macOS for named pipes (libuv 1.51 `uv__io_check_fd` rejects `S_ISFIFO` with a path, because kqueue does not report the last writer disconnecting). The reactor first treated every refusal as "ready at once", so a read from a FIFO with no writer blocked its thread (`fifo_cancel` failed on macOS, passed on Linux where epoll accepts FIFOs).

Decision: `watch_refused` in `src/runtime/io/reactor.c` fstats the refused descriptor. Only a named pipe can wait; it gets one `poll(2)` check and, if not ready, a 5 ms `uv_timer` that rechecks (the timer shares a union with the `uv_poll_t`, so rows do not grow). Files, directories and devices stay "ready at once": `poll(2)` reports a directory not ready on macOS, so polling them hung the watching-files example. The polling is a workaround (issue 4802); a non-polling path needs its own kqueue watched by `uv_poll_t`, plus a slow timer for the writer-disconnect case.

The selection line in `cmake/MsRuntime.cmake` was rewritten by an unrelated change (the libcurl move) and dropped the macOS case, so macOS CI ran mio for hours while the reactor was believed proven. Check a platform's archive for `ms_io_open` (`nm`) before calling it proven; the reactor now builds wherever `MS_LIBS_WIRED` is set, with no per-platform list, and the Unix mio poller is gone. Only a Windows MSVC host build, which links no C libraries, still has one.

Completions reach tasks through a sink: `ms_io_wait` hands each finished `ms_io_work` or `ms_io_resolve` to `ms_sched_post_completion`, which posts the result to the token the caller parked on (`ms_io_addresses_abandon` after a timed-out resolve). Work cannot be cancelled once started, so its argument must outlive the completion; at most 64 are outstanding per reactor.

The environ constructor stays (issue 4647) while CI builds against system libuv (not position independent).

Apply when: touching `src/runtime/io/reactor.c`, the platform selection in `cmake/MsRuntime.cmake`, or anything that waits on a descriptor kind libuv refuses.
