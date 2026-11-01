# Link Linux programs against a pinned glibc 2.28

## Summary

- Problem: Linux programs link against whatever `libc.so.6` the build machine has. The newest version any symbol binds to becomes the program's minimum glibc, so a program built on a 2.39 host fails to start on a 2.31 host.
- Change: link against stub `libc.so.6`, `libm.so.6` (plus `libpthread.so.0`, `libdl.so.2`, `librt.so.1` and the loader) that are generated from glibc 2.28's own ABI lists. The `_start` changes to the form that predates 2.34.
- Decision: the user asked for a floor of glibc 2.28, "sorted once and for all and properly" (thread, 2026-11-01).

## Status

Implemented, 2026-11-01, on top of `611d00a3`. An independent skeptical review returned "build after revisions", and those revisions are folded in.

## Problem

Measured on `611d00a3` (x86_64, host glibc 2.39): linking the whole runtime (`--whole-archive libms_native.a`) and running `objdump -T` gives these bindings above 2.28:

- `pthread_create`, `dlsym` and twelve more bind at GLIBC_2.34 because that release moved them into libc. They have existed since 2.2.5.
- `stat64`, `fstat64`, `lstat64` and `fstatat64` bind at 2.33. Before 2.33 they were `libc_nonshared.a` wrappers over `__xstat64`.
- `exp`, `log`, `pow` and `log2` bind at 2.29 and `hypot` at 2.35: new implementations, with the old ones still exported.
- `__libc_start_main` binds at 2.34, and our `_start` relies on 2.34's behavior of running `.init_array` itself.
- `pidfd_spawnp` (2.39), `gettid` (2.30) and `posix_spawn_file_actions_addchdir_np` (2.29) are weak references from Rust `std`, which falls back when they are absent.

So the language needs nothing newer than 2.28. The newer versions come from the host. Other effects:

- The build is not reproducible: the output depends on the host's glibc.
- `ms build` fails on a host without `libc.so.6` in the searched directories, which also rules out building in an Alpine container.
- On aarch64 the runtime defines and seeds `__stack_chk_guard` itself. glibc exports that symbol from `ld-linux-aarch64.so.1`, which we never link.

## Design

- **Tables.** `toolchain/glibc/<arch>.symbols` holds lines of the form `<soname> <version> <symbol> <F|D> [size]`.
  - The data comes from glibc 2.28's `*.abilist` files, via `toolchain/glibc/generate.sh`.
  - Each symbol gets its newest version up to 2.28.
  - Each symbol is assigned to the first library that exports it, in the order libc, libm, libpthread, libdl, librt, loader.
  - Data symbols keep their size, which copy relocations need.
- **Stubs.** On first use, `ms-clif` writes one ELF relocatable per library with the `object` crate: functions get one byte in `.text`, data gets its size in `.data`. It then links each into `<soname>` with `lld -shared -soname <soname> --version-script`.
  - Every symbol's only version is its default (`sym@@GLIBC_2.2.5`), so the program records exactly that version.
  - The stubs are cached beside the bundled linker files. The tables are bundle files, so a table change gets a new `LINKER_ID`.
- **Binding.** The link uses `-z now -z relro`, so the loader resolves every symbol before `main`. A program never fails at a later call because of lazy binding.
- **Link.** The command becomes `--dynamic-linker <loader> object --start-group runtime libunwind.a --end-group --as-needed libpthread libc libm libdl librt loader`. libpthread comes first, as with `cc -lpthread`, so on 2.28 its definitions win.
  - The search of `/lib*` and the `MS_LIBC_DIR` override are removed.
  - On glibc 2.34+, `libpthread.so.0`, `libdl.so.2` and `librt.so.1` are empty compatibility libraries, and the loader binds the old versions in libc.
- **Entry.** `_start` passes an `init` function that runs `__init_array_start..__init_array_end` with `(argc, argv, envp)`.
  - glibc before 2.34 calls `init`, and 2.34+ still calls it when it is non-null (`csu/libc-start.c`, "legacy program which supplied its own init").
  - `fini` stays null, because `_dl_fini` runs the executable's `.fini_array`.
- **Wrappers.** `entry.rs` defines `stat64`, `fstat64`, `lstat64` and `fstatat64` (and the plain-named twins, for `--link` objects; the layout is the same on LP64) over `__xstat64`, `__fxstat64`, `__lxstat64` and `__fxstatat64`, exactly as 2.28's `libc_nonshared.a` did.
  - `_STAT_VER` is 1 on x86_64 and 0 on aarch64.
  - glibc 2.33+ still exports the `__x*` functions for old programs.
- **aarch64 guard.** The `__stack_chk_guard` definition and its AT_RANDOM seeding are deleted. The loader stub exports the symbol at GLIBC_2.17, and the real loader seeds it.
- **Errors.** A symbol missing from the table is an ordinary undefined-symbol error from lld. The advice now adds that programs link against glibc 2.28, and that `--static` avoids it. An object compiled on a new host can need newer symbols (`__isoc23_strtol`), and it fails at link, never at run time.
- **Weak probes.** Rust std's weak references (`gettid`, `pidfd_spawnp`) stay unversioned and bind wherever the running glibc has them, so std's fast paths still work on new hosts.
- **Check.** A CI step builds `tests/glibc-floor/floor.ms`, which exercises threads, the resolver, stat, spawning, entropy and libm. It rejects any strong binding above 2.28 and runs the program in `almalinux:8` (glibc 2.28) on both architectures. `--static` musl is unchanged.
- **Cost accepted.** The pre-2.29 `exp`, `log` and `pow` are compatibility wrappers that run 2–20% slower on 2.39 (measured by the reviewer, 20M calls). A runtime-side math path can recover that later if a benchmark shows it matters.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `toolchain/glibc/` | generator (pinned to the `glibc-2.28` tag) and two tables | regenerating gives no diff |
| `crates/ms-clif/build.rs` | bundles the table for the host arch | `LINKER_ID` changes with it |
| `crates/ms-clif/src/link/lld/glibc_stubs.rs` | writes and caches stubs | `ms-clif` native tests |
| `crates/ms-clif/src/link/lld.rs` | links stubs, drops the host search | CI version check |
| `.github/workflows/cicd.yml`, `tests/glibc-floor/` | runs a program on glibc 2.28 | the step itself |
| `crates/ms-native/src/entry.rs` | `init`, stat wrappers, no guard | e2e, conformance, glibc 2.28 container run |
| docs and wiki | the 2.28 floor | book build |

## Alternatives

- **Do nothing.** The minimum glibc stays whatever the build host has, which is often 2.35 or newer, and builds need host files. It also keeps hand-written workarounds such as the aarch64 guard.
- **Pin 2.34.** This keeps the current `_start` and drops libpthread and libdl. It costs RHEL 8, Debian 11 and Ubuntu 20.04, all still supported, and the stub machinery is identical.
- **Pin 2.17**, Rust's own floor. It gains only end-of-life distributions, and `statx` and `getrandom` would lose their direct bindings.
- **Bundle glibc's `Scrt1.o` and `libc_nonshared.a`.** That means more files and LGPL notices for code this design replaces in about 30 lines.
- **Static musl by default.** The user decided against it: glibc is the default, and `--static` opts in.
