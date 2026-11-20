# runtime/io: the reactor on libuv

`reactor.c` is the descriptor poller the scheduler waits on, one libuv loop per scheduler thread. Design: `reactor-fit.md` in the project files (callbacks only push completion events on a ring; no scheduler code runs inside libuv).

- On glibc Linux and macOS `cargo xtask runtime` compiles this folder, folds libuv's members (from `libs.sh`) into the archive and compiles the mio poller out of `ms-rt` (cfg `ms_c = "ms_io_open"`). Musl and Windows keep mio until their library builds are proven.
- Lessons: libuv adds descriptors to epoll only inside `uv_run`, so a sleep that bypasses it (the sub-millisecond `ppoll`) must run one non-blocking pass first. A wake-up consumed by that pass must end the wait, or the scheduler sleeps with mail pending.
- `uv_poll_init` makes the descriptor non-blocking; the reactor restores the owner's flags (through `ms_sys_fd_*` in `runtime/sys/posix/fd.c`).
- A static libuv built without `-fPIC` (Debian, Ubuntu) makes the linker copy `environ` into the program while glibc updates only its own; `ms_sys_sync_environ` re-syncs it at start and after `setenv` (issue #4647; remove when the libraries are PIC).
- libuv must link against the glibc 2.28 floor: compile it with a header that sets `__GLIBC_USE_C2X_STRTOL` to 0 (see the lock script), or `sscanf` links as `__isoc23_sscanf`.
- `ring.c` is the completion ring: libuv callbacks push `(row id, kind, result)` and the scheduler pops after `uv_run`; one fixed-capacity ring and one scratch read buffer per loop, so an idle connection owns neither. `reactor.c` pushes readiness into it (a `MS_IO_READ` or `MS_IO_WRITE` event per ready descriptor, a negative result for an error or hang-up) and `ms_io_wait` folds the events of a descriptor into `(fd, bits)`; completion-style reads and writes will push their own kinds.
