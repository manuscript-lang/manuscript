[Wiki](../index.md) › [Runtime](index.md)

# The C libraries are folded into each runtime archive, found through `libs.sh`

Verified (2026-11-20, Linux glibc x86-64, system packages): `cargo xtask runtime` plans the C half per target (`plan_c_runtime`): it compiles `runtime/{sys,core,io,net,std}`, scans each source's `#include` lines (and its folder's local headers) for library headers, asks `runtime/third_party/libs.sh cflags` and `libs.sh archives <names>` for flags and static archives, and adds every member of those archives to the runtime archive, each renamed with its library's name so equal member names stay apart. The `ms` link line is unchanged and the linker takes only members a program reaches, so a program that never uses TLS carries no OpenSSL. A source whose libraries a target does not have yet (`c_libs_wired`) stays out of that archive and Rust serves it. A folder named `linux`, `glibc`, `musl`, `darwin` or `windows` under any layer is compiled for that platform only.

Why: system libraries from a current distribution call glibc newer than the 2.28 floor programs link against. The `stat` family is in `crates/ms-native/src/entry.rs`; the rest (`atexit`, `__isoc23_strtol`) is `runtime/sys/glibc/compat.c`. `toolchain/check-glibc-floor.sh` on a linked program is the check. A new library or a distribution that references another newer symbol fails the link with an undefined symbol; add it to that file.

CI: the install step is in `.github/actions/native-toolchain` (Linux so far), so every job that builds the runtime has the packages; the runtime cache key hashes the C sources, `libs.sh`, `build.sh`, `c-libs.lock` and the runner image version.

Apply when: adding a C source that uses a library, wiring a target, or changing how the archives are built. Evidence: `crates/xtask/src/main.rs`, `runtime/third_party/libs.sh`.
