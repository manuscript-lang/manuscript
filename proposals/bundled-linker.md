# Bundled linker

Status: **decided 2026-10-21** (owner direction: one bundled `lld` on every platform, built and cached by us, packaged the way Zig packages LLVM). Linux, macOS and Windows are implemented.

## Problem

`ms build` linked with the system C compiler driver (`cc`, `clang` on Windows). A machine without a C toolchain could not build any program.

## Decision

- **Linker: a pinned static `lld`**, built by manuscript-lang/llvm-bundle (LLVM 19.1.7 when written, now 23.1.1; no shared `libLLVM`, no zlib or zstd) and embedded in `ms` like the runtime archive. The Rust toolchain's own `rust-lld` was rejected: on Linux it is a launcher for a 208 MB `libLLVM.so`. wild was tried (ELF only, Mach-O arm64 experimental, no COFF) and dropped for one linker everywhere.
- **Packaging:** manuscript-lang/llvm-bundle builds lld, `opt` and `llc` per platform and publishes them with checksums to a release. `scripts/lld.lock` pins the release tag and each archive's SHA-256, `scripts/fetch-lld.sh` downloads and verifies it, and `cicd.yml` and `rust-dist.yml` call it. `crates/ms-linker/build.rs` embeds the lld found at `MS_LLD` or `target/llvm-bundle/install/bin`.
- **Linux:** static musl executables. The runtime is built for `<arch>-unknown-linux-musl`; `crt1.o`, `crti.o`, `crtn.o`, `libc.a` and `libunwind.a` come from the toolchain's `self-contained` directory (debug info stripped) and are embedded with lld. `--gc-sections`, `--strip-all` (MinSizeRel) as before.
- **macOS:** `ld64.lld` against `.tbd` stubs for libSystem, Security and CoreFoundation, generated per link from the symbols the program and runtime import but do not define (Apple's SDK is not redistributable). `-dead_strip`, `-x` (MinSizeRel); lld ad-hoc signs arm64 output. `dsymutil` stays optional.
- **Windows:** the same lld in `ld.lld` (mingw) mode over llvm-mingw's startup object, CRT, unwinder and import libraries, with the runtime built for `<arch>-pc-windows-gnullvm`. Chosen over generating import libraries for the MSVC ABI because that ABI also needs `vcruntime140` (C++ exception and CRT helpers), which is not part of Windows and is redistributable only as a separate install, and a static replacement means the SDK; the mingw CRT binds to `ucrtbase.dll`, which ships with Windows 10. `--gc-sections` replaces `/opt:ref`; DWARF stays in the image. `scripts/fetch-mingw.sh` pins the release by checksum.
- **No new options.** `MS_LINKER` is gone.

## Evidence (Linux, x86_64)

- Empty program, MinSizeRel: 426 KB static ELF, linked with an empty `PATH`.
- `bench/perf/kernels`, glibc and `cc` against musl and lld on the same machine: sieve 35.5 vs 30.3, nbody 11.1 vs 10.2, matmul 14.3 vs 14.1, trees 62.5 vs 59.5, collatz 344 vs 293, map 32.8 vs 33.8 ms: noise, no musl allocator regression.
- The conformance corpus passes on the musl build; the ms-clif native, DWARF and fault-trace tests link with the bundled lld (their C shims compile with `-D_FORTIFY_SOURCE=0` because musl has no `*_chk` entry points).

## Review findings carried forward

- musl resolves names without NSS, like Go's pure resolver; accepted. Static non-PIE; `dlopen` is unavailable in the runtime.
- Windows programs depend on `ucrtbase.dll` (Windows 10 and later).
- Building `ms` from source still needs a C compiler (`ring`) and now a static lld.
