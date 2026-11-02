# Trim the runtime ABI: generated signatures, one prefix rule, fewer crates

## Summary

- Problem: `crates/ms-rt/SYMBOLS.md` was a hand-written copy of every exported signature, 230 std natives broke the `msrt_`/`msstd_` split in `crates/DESIGN.md`, and `ms_abi.h` repeated layout constants by hand.
- Change: generate the signature table and the C header from the Rust sources, rename std natives to `msstd_*`, and merge three tiny `ms-std-*` crates.
- Decision requested: none; Chinmay directed the removal of the markdown catalogue and chose the macro-emitted route (2026-11-01).

## Status

Implemented 2026-11-01 on `claude/project-thread-ethgrl`. Not done here: removing symbols proved dead, and inlining `bits_*`/`hash_*` (each needs a `bench/perf` before and after).

## Problem

- Verified: `ms-lower/build.rs` parsed `SYMBOLS.md`; its test compared names only, so a signature edit without the markdown edit segfaulted compiled calls (`wiki/runtime/a-native-signature-change-needs-a-regenerated-table-and-a-fre.md`).
- Verified: 220 symbols in `ms-std-net`, `-json`, `-crypto`, `-path`, `-html`, `-compress`, `-regex`, `-url`, `-archive` and `-encoding` were named `msrt_*` although `DESIGN.md` reserves that prefix for `ms-rt`.
- Verified: `crates/ms-rt-abi/include/ms_abi.h` repeated the string tag shift and length mask by hand.

## Design

- The `native!` macro (`crates/ms-rt/src/ffi/native.rs`) emits a test per shim that records its parameter names and `type_name` of each raw ABI type. A scan of plain `extern "C"` functions covers the rest. `cargo xtask symbols` merges both into `crates/ms-lower/rt_symbols.txt`, which `build.rs` turns into the lookup table; `--check` runs in `make check`.
- `ms-rt-hot` functions take integers so LLVM can inline them; a `/// C view:` line above each records the pointer types lowering marshals with.
- Lowering matched a few type spellings by name (`*const Obj`, `*mut Handle<`); they now match `*const ObjCell<` and `*mut ObjCell<`.
- `ms_abi.h` is built by the `header_is_current` test from `ms-rt-abi` constants (`MS_UPDATE_HEADER=1` rewrites it) and gains `MS_STATUS_*`, `MS_ABI_VERSION` and static layout asserts.
- Rename: every std-defined `msrt_<module>_*` becomes `msstd_<module>_*` in crates, stdlib imports, lowering and `ms-mir`'s unwind prefixes.
- `ms-std-math`, `ms-std-random` and `ms-std-encoding` become modules of `ms-std-core`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt` | `native_signature!`, `record_signature` | `cargo xtask symbols --check` |
| `crates/xtask` | `symbols` step | same |
| `crates/ms-lower` | table from `rt_symbols.txt`; `ObjCell<` spellings | `make e2e` |
| `crates/ms-cli/tests/runtime_symbols.rs` | compares archive exports with the table | itself |
| `crates/ms-rt-abi` | header generator | `header_is_current` |
| `crates/ms-std-*` | rename, three-crate merge | `make e2e`, crate tests |

## Alternatives

- Do nothing: keeps a silent segfault on a forgotten markdown edit.
- Scan sources only: cannot see the raw type behind `ObjRef<T>` or `Out<T>`.
- Derive signatures from stdlib `extern fn`: a lowering rewrite; intrinsic methods would still need a table.
- `cbindgen` for the header: a new dependency for a 70-line header.

## Open questions

- Windows-only natives are invisible to a Linux run of `symbols`; none exist today, and the archive test on Windows fails if one appears.
