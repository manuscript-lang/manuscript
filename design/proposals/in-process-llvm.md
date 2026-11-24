# In-process LLVM

## Summary

- Problem: every LLVM build spawns `opt` and `llc` (twice with fault tables), each re-reading its input, and an LLVM crash is a bare child-process failure.
- Change: with `MS_LLVM` naming a pinned shared LLVM library, `ms` loads it through `base/dylib` and runs the optimizer and code generator through its C API. An installed `ms` loads the library shipped in `lib/ms/lib` by default; `MS_LLVM=none` or a library that does not load keeps the `opt`/`llc` process route. `lld` stays a child process.
- Decision requested: merge the loader and the pin; benefit is small, so the review question is whether that is worth the code.

## Status

Proposal, 2026-11-23, after the Debug pipeline change (#6542). Owner direction (Chinmay, 2026-11-22): the in-process part is ours; Linux, macOS and Windows stay at parity. Stage 4 (fault tables from the object) was measured and dropped, see Evidence.

## Problem

- Two process launches and file round trips per build; an `opt` or `llc` abort shows as a failed child, not an `ms` error.
- The pinned `opt`/`llc` and the `lld` already ship from llvm-bundle; a shared library from the same release removes the need for them at run time.

## Design

- `src/base/dylib.[ch]`: `ms_dylib_open` (absolute paths only, never searched), `ms_dylib_symbol`, `ms_dylib_close`, over libuv.
- `src/compiler/link/llvm_inproc.[ch]`: resolves the C API once, parses IR, runs `LLVMRunPasses`, emits an object or assembly into memory. Process-global `cl::opts` are restated on every call. `LLVMInstallFatalErrorHandler` reports an LLVM fatal error as an `ms` internal compiler error with the fault exit status.
- `MS_LLVM` names the library file (a library that fails to load is an error), `none` selects the `opt`/`llc` route, and unset uses the installed library when it loads, else that route. `toolchain/llvm-lib.lock` pins the llvm-bundle tag and SHA-256 per platform, `tools/fetch-llvm-lib.ms` fetches it, and the CI toolchain action exports `MS_LLVM`.
- Pipelines match the process route: Debug `function(sroa,...)` with `-O1`, basic register allocator; Release `default<O3>`.

## Evidence

- Conformance with `MS_LLVM` set matched the process route on the same tree (no new failures).
- Measured (html-oracle IR, 30 MB, Release): `opt` 15 s, `llc -O3` 8.8 s, the second assemble pass 0.7 s. Process launch is milliseconds, so in-process saves little time; the build time is LLVM work.
- Dropped stage 4 (fault tables from `.debug_line` and object symbols): it would remove only the 0.7 s pass and the assembly scanner, at the cost of three object-format readers.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/base` | `dylib` | `base_dylib` unit test with a probe library |
| `src/compiler/link` | `llvm_inproc`, `object.c` routing | conformance corpus with `MS_LLVM` set |
| `src/cli/pipeline.c` | read `MS_LLVM` | same |
| `toolchain/`, `.github/actions/toolchain` | lock, fetch script, env | CI on all platforms |

## Alternatives

- Do nothing: no loader to maintain; build time is unchanged either way.
- Static LLVM inside `ms`: 100+ MB binary and an LLVM build in every `ms` build.
- Rust `inkwell`/`llvm-sys`: a new dependency; the C API through `dylib` needs none.

## Open questions

- Installed layout: the dist ships `lib/ms/lib/libLLVM.*` (`bin/LLVM-C.dll` on Windows) and `llc` (the glibc stubs), not `opt`. Compile time per platform (bench-llvm-route, 7 runs): Linux and macOS about 1.0x, Windows 1.0 to 1.7x; the default is chosen for the saved disk round trip and LLVM faults reported as `ms` errors, not speed.
- macOS library validation and the Windows `LLVM-C.dll` exports are checked by the platform CI runs on this PR, not assumed.
