# Bundled linker

## Problem

`ms build` links with the system C compiler driver (`cc`, `clang` on Windows) over the object file and the embedded runtime archive (`crates/ms-clif/src/link.rs`). A machine without a C toolchain cannot build any program, and `MS_LINKER` exists only to point at a different one. The goal is that `ms` alone builds programs on Linux, macOS and Windows, with no new user-facing option.

## Outcome of the Linux spike (supersedes the `rust-lld` choice below)

`rust-lld` cannot be embedded: on Linux it is a 12 MB launcher that loads a 208 MB `libLLVM.so` from the toolchain. Linux therefore links **in-process with wild** (`libwild`, a Rust linker library, ELF x86_64 and aarch64), over the musl startup files and libc copied from the toolchain by `crates/ms-clif/build.rs`. Measured: an empty program links to 426 KB (MinSizeRel) with an empty `PATH`; the kernels benchmark and the conformance corpus pass. In-process linking exposes an `ETXTBSY` race when another thread forks while the output is open, so `ms` retries a spawn of a freshly linked program briefly. macOS and Windows need their own answer (wild has experimental Mach-O arm64 support, none for COFF); until then they keep the system C compiler driver.

## Proposal

**Linker: embed `rust-lld`.** It is the LLVM `lld` the Rust toolchain already ships (ELF, Mach-O, COFF/MinGW flavors in one 11.9 MB binary on Linux; 3.3 MB gzipped). `ms-cli/build.rs` copies it from the pinned toolchain's sysroot (`rustlib/<host>/bin/rust-lld`, present in the `minimal` profile) and embeds it exactly as `libms_native.a` is embedded today: extracted once to `~/.cache/ms/` by content id, then run as a subprocess with `-flavor`. No new knob; `MS_LINKER` is removed (a system driver can no longer link a runtime built for a different libc).

**Libc and system libraries, per platform:**

| Platform | Runtime target | Startup and libc | Notes |
| --- | --- | --- | --- |
| Linux | `<arch>-unknown-linux-musl` | `crt1.o`, `crti.o`, `crtn.o`, `libc.a`, `libunwind.a` from Rust's `self-contained` musl directory, embedded with the runtime | Fully static, non-PIE; no libc on the machine is needed. |
| macOS | host triple | Stub `.tbd` files for `libSystem` (libc, libm, pthread, dl), `Security` and `CoreFoundation`, written by `ms` at link time from the symbols the object and runtime import, then linked with `ld64.lld` | Apple's SDK is not redistributable, so stubs are generated, not copied. `lld` ad-hoc signs arm64 output. `dsymutil` stays optional: without it, no `.dSYM` (the profiler uses its own PC-to-source table). |
| Windows | `<arch>-pc-windows-gnu` | Rust's self-contained MinGW startup objects and import libraries (`kernel32`, `ws2_32`, `bcrypt`, …) | Replaces the MSVC import libraries that are only available with Visual Studio or the SDK. DWARF sections are kept, as `/debug:dwarf` does today. |

`--gc-sections` / `-dead_strip` / `--strip-all` for MinSizeRel stay as in #909 and #913.

## Evidence (Linux, this checkout)

- `ms-native` builds for `x86_64-unknown-linux-musl` unchanged (only `ring` needs a C compiler at *build* time).
- `rust-lld -flavor gnu -static --gc-sections` over the existing object, the musl archive and the self-contained musl files produces a working 421 KB static executable with no `cc` involved.
- `bench/perf/kernels` on the same machine, glibc/`cc` vs musl/`rust-lld` (ms): sieve 35.5 vs 30.3, nbody 11.1 vs 10.2, life 27.4 vs 31.3, matmul 14.3 vs 14.1, trees 62.5 vs 59.5, collatz 344 vs 293, map 32.8 vs 33.8. Run-to-run noise, no musl allocator regression on these kernels.

## Alternatives

- **Do nothing**: keeps the C toolchain requirement. Rejected by the goal.
- **wild** (Rust linker): ELF only, no Mach-O or COFF, so it cannot cover macOS and Windows; adds a second linker.
- **lld as an in-process library**: no stable library API; vendoring LLVM adds a very large build dependency. A subprocess of the already-shipped binary gets the same result.
- **Keep glibc on Linux**: needs `crt1.o`/`libc.so` from `libc6-dev`, which is the toolchain being removed.
- **Windows MSVC target with generated import libs**: `lld-link` cannot create import libraries from `.def` files and no `llvm-dlltool` ships with Rust.

## Risks

- Windows and macOS cannot be exercised locally; CI on both is the evidence, so each lands as its own PR.
- Building `ms` from source still needs a C compiler for `ring` (all platforms) and the musl target in the build toolchain (`rust-toolchain.toml` gains `targets`). Users of release binaries need neither.
- musl differences: `getaddrinfo`, locale and `dlopen` behave differently in a static binary; the standard-library conformance corpus runs on the musl build before merging.
- Size: `ms` grows by the `rust-lld` payload (about 3 to 12 MB, depending on compression) on top of the 45 MB embedded runtime archive.

## Review outcome (skeptical reviewer)

Accepted: macOS and Windows are riskier than Linux and unmeasured here, so each gets its own spike and PR and none blocks Linux. Windows arm64 has no `-pc-windows-gnu` target, so the Windows design keeps the MSVC ABI and needs generated import libraries; the `windows-gnu` row above is a candidate for x86_64 only until a CI spike links the corpus. macOS `dsymutil` stays required for `.dSYM` until the stub spike proves an alternative. Tests and scripts that call host `cc` move to the bundled linker or stay test-only. Linux gets glibc-layout audits (`sigaction`, `ucontext` offsets, `malloc_usable_size`) and a musl fault/profile test before merge.

Rejected: "keep `cc`, fall back to `rust-lld` when absent". It keeps two libc targets and two runtime archives alive and leaves the glibc path untested wherever the fallback is used; one bundled path is smaller and the only one that is the same on every machine. musl DNS (no NSS) matches Go's pure resolver behavior and is accepted.

## Plan

1. Linux: musl runtime, embedded `rust-lld` and startup files, remove `MS_LINKER` and the `cc` path, CI without a C compiler for linking.
2. macOS: generated stubs, `ld64.lld`, optional `dsymutil`.
3. Windows: `windows-gnu` runtime and MinGW-flavor `lld`.
4. README and docs stop requiring a C compiler.
