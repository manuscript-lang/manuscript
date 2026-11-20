# runtime/io: the reactor on libuv

`reactor.c` is the descriptor poller the scheduler waits on, one libuv loop per scheduler thread. Design: `reactor-fit.md` in the project files (callbacks only push `(fd, bits)` on a ready ring; no scheduler code runs inside libuv).

- Selected when `MS_UV_DIR` names a folder with `lib/libuv.a` and `include/uv.h`: `cargo xtask runtime` then compiles this folder, adds libuv's objects to the archive and compiles the mio poller out of `ms-rt` (cfg `ms_c = "msio_open"`). Glibc Linux only so far; Windows, macOS and musl keep mio until `io` builds there.
- Lessons: libuv adds descriptors to epoll only inside `uv_run`, so a sleep that bypasses it (the sub-millisecond `ppoll`) must run one non-blocking pass first. A wake-up consumed by that pass must end the wait, or the scheduler sleeps with mail pending.
- `uv_poll_init` makes the descriptor non-blocking; the reactor restores the owner's flags.
- libuv must link against the glibc 2.28 floor: compile it with a header that sets `__GLIBC_USE_C2X_STRTOL` to 0 (see the lock script), or `sscanf` links as `__isoc23_sscanf`.
