[Wiki](../index.md) › [Runtime](index.md)

# The C libraries are folded into each runtime archive, found by CMake

Verified (2026-11-20, Linux glibc and musl x86-64): `cmake -P cmake/BuildRuntime.cmake` builds the C half per target with the CMake project (`CMakeLists.txt`, `cmake/`, Ninja, ccache when installed; `build_c_runtime` in `src/runtime/build_c.rs`): `cmake/MsRuntime.cmake` globs `src/runtime/{sys,core,io,net,std}`, scans each source's `#include` lines (and its folder's local headers) for library headers, gets flags and static archives from `cmake/MsLibs.cmake` (pkg-config, or a prefix folder), and `cmake/FoldArchives.cmake` leaves `c-objects.txt` listing our objects (renamed with a number, since `ar` keys members by base name) and every member of those archives to the runtime archive, each renamed with its library's name so equal member names stay apart. The `ms` link line is unchanged and the linker takes only members a program reaches, so a program that never uses TLS carries no OpenSSL. A source whose libraries a target does not have yet (`MS_LIBS_WIRED` in `cmake/MsPlatform.cmake`) stays out of that archive and Rust serves it. A folder named `linux`, `glibc`, `musl`, `darwin` or `windows` under any layer is compiled for that platform only.

Why: system libraries from a current distribution call glibc newer than the 2.28 floor programs link against. The `stat` family is in `crates/ms-native/src/entry.rs`; the rest (`atexit`, `__isoc23_strtol`, aarch64 `pthread_atfork`) is `src/runtime/sys/glibc/compat.c`. `toolchain/check-glibc-floor.sh` on a linked program is the check. A new library or a distribution that references another newer symbol fails the link with an undefined symbol; add it to that file.

Vendored (2026-11-20, Chinmay): the six libraries live in `src/runtime/third_party/<name>` and `build.sh <triple>` builds them for every target, so every runtime archive uses the same sources. A prebuilt-and-published design (per-target archives fetched by checksum, like the LLVM tools) was built and dropped: a build is under two minutes, and he preferred vendoring to a publish-then-pin step. Libraries cannot be swapped between libc's at link time (headers fix struct layouts and symbols), so glibc and musl each build their own; `--static` needs musl.

musl: the musl archive takes pinned builds (`MS_C_LIBS=pinned`, `CC=musl-gcc` from `musl-tools`; `cmake/BuildRuntime.cmake` runs `build.sh` for a musl triple and hands CMake the folder as `MS_LIBS_PREFIX`), because system packages are glibc's and musl needs musl's headers. The pinned OpenSSL is `no-secure-memory`: musl-gcc cannot see `<linux/mman.h>`. Static programs link and run with the libuv reactor on.

CI: the install step is in `.github/actions/native-toolchain` (Linux so far), so every job that builds the runtime has the packages; the pinned musl libraries are cached on `build.sh key <musl triple>`; ccache objects ride in the sccache cache entry (`.github/actions/sccache`) and in a `c-test` entry of their own; the runtime cache key hashes the C sources, `CMakeLists.txt`, `cmake/`, `build.sh`, `c-libs.lock` and the runner image version.

Parallel builds: `cmake -P cmake/BuildRuntime.cmake` builds the glibc, musl and profiling archives side by side, and each asks `build.sh` for the same output folder. `build.sh` takes an `mkdir` lock (`<folder>.lock`); the others wait for `.complete`. Without it two runs wrote `include/llhttp.h` at once ("File exists", linux-arm64 CI).


Adding files: a `.c` under `src/runtime/{sys,core,io,net,std}` is picked up by glob; only a new test needs a line in `cmake/MsTests.cmake` (core, std and io tests by name pattern need none), and a new fuzz harness needs its dependency list there.

Apply when: adding a C source that uses a library, wiring a target, or changing how the archives are built. Evidence: `cmake/BuildRuntime.cmake`, `cmake/`.
