# runtime/io: the reactor on libuv

`reactor.c` is the descriptor poller the scheduler waits on, one libuv loop per scheduler thread. Design: `reactor-fit.md` in the project files (callbacks only push `(fd, bits)` on a ready ring; no scheduler code runs inside libuv).

- Opt-in while it is proven: `MS_C_REACTOR=1 cargo xtask runtime` compiles this folder, folds libuv's members (from `libs.sh`) into the archive and compiles the mio poller out of `ms-rt` (cfg `ms_c = "ms_io_open"`). Glibc Linux only so far; musl, macOS and Windows keep mio until their library builds are wired. With it on, `ms test` fails every test ("the test process exited with status 0 before this test started") where the mio build passes; it becomes the default when that is fixed.
- Lessons: libuv adds descriptors to epoll only inside `uv_run`, so a sleep that bypasses it (the sub-millisecond `ppoll`) must run one non-blocking pass first. A wake-up consumed by that pass must end the wait, or the scheduler sleeps with mail pending.
- `uv_poll_init` makes the descriptor non-blocking; the reactor restores the owner's flags (through `mssys_fd_*` in `runtime/sys/fd.c`).
- A static libuv built without `-fPIC` (Debian, Ubuntu) makes the linker copy `environ` into the program while glibc updates only its own; `mssys_sync_environ` re-syncs it at start and after `setenv` (issue #4647; remove when the libraries are PIC).
- libuv must link against the glibc 2.28 floor: compile it with a header that sets `__GLIBC_USE_C2X_STRTOL` to 0 (see the lock script), or `sscanf` links as `__isoc23_sscanf`.
