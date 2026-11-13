# Emit LLVM IR directly from MIR

## Summary

- Problem: a release build lowers MIR to Cranelift IR and then translates that, line by line, to LLVM text. Cranelift IR has no record types, so every record is a bag of scalars and LLVM gets huge, mostly redundant IR.
- Change: a second backend, `mir_llvm`, that emits LLVM IR from MIR with typed records, `memcpy` for copies and `ptr` for addresses. The Cranelift debug path is untouched.
- Cost: a port of the op lowering (about 4k lines) and a differential harness. Staged; each stage lands behind a flag and falls back per function to the old path.
- Gate (after stage 3): stop unless the yaml IR is at least 2x smaller than the `MS_VECTORIZE=off` baseline (122k lines), its release build is at least 1.5x faster, and no `bench/perf` kernel is slower by more than 15% (the measured layout noise between identical builds is 11%; use interleaved runs). Report the share of functions emitted directly, so fallback functions do not flatter the numbers. Add one compute-heavy program besides yaml.
- Decision already made: Chinmay, 2026-11-13, "let's translate MIR to LLVM IR directly". This reverses the earlier standing rule against a new direct emitter. Plan source: `architecture/mir-to-llvm-direct-plan-2026-11-12.md`.

## Direction (Chinmay, 2026-11-13)

The LLVM IR is not constrained by Cranelift compatibility: use LLVM's own features (typed structs, `memcpy`, `getelementptr inbounds nuw`, `noalias`/`readonly`/`nocapture`/`dereferenceable` and `nonnull` attributes, `!range`, `!tbaa` and loop metadata, `cold`/`noreturn`, intrinsics) wherever they say more than the scalar leaves do. Cranelift stays the debug backend and the oracle for program behavior (same output and exit code), not a source of ABI or layout rules. While functions fall back one by one, a direct function and a translated one still call each other through the leaf signature; the signature changes (records by pointer, hidden result pointers) land with a thunk at that boundary, or once the translation is deleted.

## Problem

Measured on `main` (76dd1fbb), linux/amd64, `@std/data/yaml` parse program, `MS_KEEP_LL=1`:

| | Lines |
| --- | ---: |
| MIR (`ms emit`) | 18,963 |
| LLVM IR handed to `opt` (3 units + main) | 183,081 |
| of which per-CPU AVX2 copies | 53,876 (31%) |
| `load` instructions | 37,163 |
| `memcpy` calls | 26 |

Largest functions: `flow_value` 17,644 lines per copy, `sequence_items` 14,754, `block` 14,251. `Flow` is a 456-byte record of 57 scalars; every whole-record read is 57 loads (and 57 stores for a write), and `flow_value` reads it 92 times.

Release build wall time of this program is 2.9 s with and without AVX2 copies (warm, same machine, one run each), against 0.6 s on Cranelift. So dropping the copies cuts lines by a third but not time: line count alone does not explain compile time, and stage 3 must show a time drop, not only a line drop. The 28% dead-load figure from the coordinator is unverified here and is not used.

Cause (`crates/ms-clif/src/layout.rs`): a MIR value is flattened to scalar leaves; the Cranelift lowering and then `llvm_ir.rs` see only leaves. Nothing tells LLVM that the 57 loads are one 456-byte object, so there is no `memcpy`, no `sroa` on a typed alloca, and no `noalias readonly` on a borrowed record.

## Design

```
MIR -> ms-clif lowering -> CLIF -> object        (debug; unchanged)
MIR -> mir_llvm         -> LLVM IR text -> opt/llc   (release; new)
```

- Home: module `crates/ms-clif/src/mir_llvm/`, not a new crate. It needs `Gen` (symbols, glue ids, fault tables) and `layout.rs`; a separate crate would depend on `ms-clif` while `cg.rs` calls it. Move it out when the neutral layout module exists.
- Debug info and tables: direct functions go through the same `LlvmModule` (`DISubprogram` with the linkage name, `DILocation` on every call, `defs`, `llvm_funcs`, the `.avx2`/`.base` scheme), because the fault-table reader finds functions by DWARF symbol. Glue has no MIR and stays on the old path until stage 4. Mixed TBAA: functions from the old path keep their two regions; typed tags are only added in stage 3 together with a check that no old-path function touches the same memory untagged.
- Hook: `prepare` in `cg.rs` already routes each function to LLVM. With `MS_LLVM_DIRECT`, `mir_llvm::try_function(f)` runs first and returns `None` for any function it cannot yet emit; that function takes the old path. Both paths keep the same leaf calling convention in stage 2, so a direct function and a translated one call each other.
- Value classes: a value of at most N leaves is SSA (N chosen by measurement; start with 1, alloca above) (scalars, or a struct of them). A larger record lives in one `alloca` of its LLVM struct type; copies are `memcpy`, a field read is a `getelementptr` and a `load`, a field write a `getelementptr` and a `store`. This is how rustc treats large aggregates.
- Types: one named LLVM struct per record and alternative, built from the same leaf layout as `mem_layout`, so offsets and sizes agree with the runtime and the Cranelift object by construction (asserted in a test).
- Facts (stage 3, each with a golden test): `nonnull dereferenceable(N) align A` on record pointers; `noalias readonly nocapture` on borrowed pointer parameters; struct-path TBAA per (record, field). Start with `readonly` only; add `noalias` per fact with a test, since a wrong one is a silent miscompile.
- Memory model: no change. Borrow parameters are not written during the call; `var` parameters are exclusive; `.clone()` stays the only copy and emits a clone call, never a bare `memcpy` of an owner.

## Calling convention (one design for records, lists, glue and closures)

Direct functions call each other through an LLVM-native signature; the leaf signature stays only where the runtime or a translated function calls in. Owner of the code: the records thread, in `crates/ms-clif/src/abi_llvm.rs` (`classify(ty, mode) -> Pass`, `ret(ty) -> Ret`, attribute strings), used by everyone else.

- Size classes, from `mem_layout` (so layout, runtime and Cranelift agree): a value of at most 16 bytes is scalars (`Int`, `Float`, `Bool`, sized integers as `i64`/`double` registers, `String` as two params `ptr`, `i64`); anything larger (every list, 24 bytes; records and alternatives above two words) is indirect. The 16-byte threshold is a start, changed only by measurement.
- Borrow, indirect: `ptr nonnull readonly nocapture align A dereferenceable(N)`. No `noalias` until the borrow rules are proven for `scoped` closures (open point), with a golden test per added fact.
- Move, indirect: the caller passes a pointer to a temporary it owns and no longer uses: `ptr nonnull nocapture noalias align A dereferenceable(N)`. No `byval`: that is a copy the move does not need, and a clone is always an explicit call.
- Var, indirect or scalar: `ptr nonnull nocapture noalias align A dereferenceable(N)` to the variable's slot, updated in place; the "final value returned after the result" of MIR becomes a store at each `ret`, and the caller reads the slot after the call. Scalar `var` parameters use the same pointer.
- Result: at most 16 bytes returns as scalars or an anonymous `{ .. }` (two registers); larger is a hidden first parameter `ptr sret(%T) noalias nocapture nonnull align A dereferenceable(N)`.
- Types: a named struct per record and alternative (`mem_layout` field order and offsets), `%List = type { ptr, i64, i64 }`, accesses by `getelementptr inbounds nuw` and `load`/`store` with explicit `align`, copies by `memcpy` with alignment (never leaf by leaf).
- Boundary: a function `f` whose address escapes, which the runtime calls (closures, vtable methods, comparators, entry points), or which a translated function calls, gets a thunk. The native body is `internal` `@"f.n"`; `@"f"` keeps today's leaf signature and forwards to it, so LLVM inlines the native body into the thunk's callers. Direct to direct calls name `@"f.n"`. When the translation is deleted the thunks go and the names swap. The runtime's `msrt_*` entry points keep the C leaf ABI.
- Calls of `internal` functions that never escape may use `fastcc`, adopted only with a measured gain.
- Fault sites, `DISubprogram` and profile tables are found by the symbol and DWARF subprogram of `@"f.n"`; the thunk carries none.

## Stages

1. Skeleton and harness (this PR): `mir_llvm` with scalar ops, comparisons, branches, block parameters and direct calls; per-function fallback; flag; a differential check that runs fixtures with and without the flag and compares output.
2. Records: typed structs, alloca and `memcpy`, `rec.get/set/new`, optionals and alternatives, strings and lists as `{ptr, len, cap}` structs.
3. Facts and the calling convention: records above a size chosen by measurement pass by pointer. This changes the shared signature builder, so it also changes the Cranelift lowering and the exclusive-parameter indexes (`set_exclusive`); that is a real cost to the debug path, taken only if stage 2 alone misses the gate. Large returns use a hidden result pointer. First facts. Measure: this is the gate.
4. Glue, data objects, vtables, closures, faults and per-CPU copies. Per-CPU copies stay, but are made by cloning the finished function once after `opt` shows a loop, not by emitting twice.
5. Loop markers and range facts. 6. Delete `llvm_ir.rs`'s instruction layer. 7. `bench/perf` before and after.

## Alternatives considered

- Do nothing: yaml release builds stay at about 2.9 s and grow with every record field.
- Fix the translation: drop dead loads, merge adjacent leaf loads into one wide load, skip AVX2 copies of cold functions. Cheap, and it likely removes half the lines. It cannot give LLVM record types, `memcpy` or borrow facts, because the information is gone before the translation sees it. These are cheap and should be tried first as a measured baseline: AVX2 copies off already gives 122k lines, and the gate above is set against that number. They cannot give LLVM record types, `memcpy` or borrow facts.
- Pass records by pointer only in the new backend: needs a thunk at the boundary with translated functions (they still take leaves) until the translation is deleted; cheaper than constraining the IR to the leaf signature.
- New crate now: blocked by the dependency direction above.

## Testing

- `opt -verify` on every emitted unit; the conformance corpus and `bench/perf` kernels run with the flag on and compared to the flag off (output and exit code).
- One golden fixture per fact (stage 3): the attribute is present, and a missed case is not given it.
- Cost check per stage: IR lines and release build time for the yaml program, recorded in `bench/compile-time/`.
- Linux, macOS and Windows stay at parity; no gating. Windows and macOS CI is dispatched on the branch before any stage is called done.

## Builder: in-house, no inkwell (Chinmay, 2026-11-13)

Chinmay asked for `inkwell`, then chose the in-house builder, tried the `inkwell` plan once more, and settled on generating LLVM IR text directly: `crates/ms-clif/src/llvm_build.rs` is the builder. Reasons `inkwell` was dropped, measured 2026-11-13:

- It links LLVM into `ms` at build time: every platform's build needs the LLVM 23 headers, static libraries and `llvm-config`. A distribution install lacks some static libraries (Polly), the glibc 2.28 floor needs LLVM built in the manylinux_2_28 container, and Windows has no ready static libraries.
- Binary size on Linux amd64, stripped: about +4 MB to build IR only, about +54 MB with the optimizer and code generator in process (today's `ms` is 44.5 MB; `opt`, `llc` and `lld` are downloaded separately).
- It does not choose alignment (a scratch `i64` load came out `align 4`); the in-house builder takes alignment on every access.

Revisit only if a goal needs LLVM in process (dropping the downloaded `opt` and `llc`).

## Open points

- Whether the neutral layout module should be extracted before stage 3.
- Whether record `noalias` can be proven for borrows that reach `scoped` closures; until then `readonly` only.
