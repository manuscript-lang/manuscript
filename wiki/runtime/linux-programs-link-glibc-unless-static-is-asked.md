# Linux programs link glibc unless `--static` is asked

Decision (user, 2026-11-01): Linux programs link the system glibc dynamically; musl is linked only with `--static`.

Why: static musl's resolver looks up `/etc/hosts` case-sensitively (`lookup("LocalHost")` failed), and its NSS, locale and allocator differ from what Linux users expect. Verified: the same program resolves under glibc and fails under `--static`.

Decision (user, 2026-11-01): the floor is glibc 2.28, fixed once, independent of the build host ([proposal](../../proposals/glibc-2-28-floor.md)).

Mechanism:
- Archives: `cargo xtask runtime` builds `libms_native.a` for `<arch>-unknown-linux-gnu` and `libms_native_musl.a` for musl, and `ms` embeds both.
- Stubs: lld links against stub glibc libraries that `ms-clif` generates from `toolchain/glibc/<arch>.symbols` (glibc 2.28's ABI lists, made by `generate.sh`). It never reads the host's `libc.so.6`.
- Binding: every symbol binds at its newest version up to 2.28, and `-z now` resolves all of them at load.
- Entry: the gnu archive defines what `crt1.o` and `libc_nonshared.a` would (`crates/ms-native/src/entry.rs`): `_start` with an `.init_array` runner (glibc before 2.34 does not run it), and `stat64` and friends over `__xstat64`. The aarch64 `__stack_chk_guard` comes from the loader stub.
- Libraries: on 2.34+, `libpthread.so.0` and `libdl.so.2` are empty compatibility libraries, and the old versions bind in libc.
- Weak `std` probes (`gettid`, `pidfd_*`) stay unversioned, so they bind wherever the host has them.
- Tests: C-fixture runtimes define no entry and link musl through `link_libc`.

Failure modes:
- A `--link` object compiled against a newer glibc can need a symbol 2.28 lacks (`__isoc23_strtol`). It fails at link, never at run time.
- The pre-2.29 `exp`/`log`/`pow` are glibc's compatibility wrappers, a few percent slower.

Verify: CI's "Programs run on glibc 2.28" step builds `tests/glibc-floor/floor.ms`, checks that `objdump -T` shows no strong version above 2.28, and runs it in `almalinux:8`.
