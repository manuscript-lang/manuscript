# Proposal: incremental builds (code generation cache)

## Summary

- A second `ms build` with nothing changed redoes all work (8.0 s Debug, 40 packages, 122k lines); Go rebuilds after a one-file touch in 0.23 s.
- Of a Debug build, 4.5 s is Cranelift `define_function` over 12,006 functions; the front end plus lowering is about 3 s; link is 0.13 s (measured below).
- Stages: timings, a whole-build short cut keyed by the final MIR and every codegen input, parallel Cranelift, then (only if numbers justify it) a content-addressed per-function cache.
- Release builds are not helped by this: 97% of a 293 s Release build is one LLVM `opt` + `llc` over one module. A partitioned, cached LLVM stage is Stage 3 and is a separate decision.
- Decision requested: build Stages 0 to 2 now; Stage 3 after Stage 0/2 numbers.

## Status

Proposal; Stages 0 to 2 implemented, 2026-10-31, checked against `f57bac39`. Direction (Chinmay, project chat): "incremental builds are the first priority we can do others later". Review outcome: see Review at the end.

## Problem

Measured on 4 cores with `bench/compile-time/gen.py 40 25 10` (PR #2103), `ms` release build of `f57bac39`:

| Step | Time |
| --- | --- |
| `ms check` | 1.8 s |
| `ms emit` (+ lower to MIR) | 2.4 s |
| `ms build --build-type Debug`, first and second run (identical) | 11.1 s, 8.0 s |
| of which MIR optimize + unwind | 0.2 s |
| of which Cranelift lowering to CLIF (`Lower::lower_func`) | 0.5 s |
| of which Cranelift `define_function` + tables | 4.5 s |
| of which write object + link | 0.13 s |
| `ms build`, Cranelift release | 10.2 s |
| `ms build`, LLVM release | 293 s (in PR #2103) |

- `.ms-cache` holds nothing at object level, so every build is cold.
- Non-goals: parallel Cranelift or LLVM (a separate stage, independent of caching); caching the front end (1.8 s check; revisit after Stage 2); changing generated code.

## Design

One rule: **a function's machine code is a pure function of its normalized Cranelift IR, the ISA flags and the compiler version; cache it by that hash.**

```text
MIR fn -> Lower -> CLIF fn --normalize--> key
                                         |
                    hit:  bytes + relocs by symbol name + line/scope rows -> define_function_bytes
                    miss: define_function -> store the same triple
```

- **Key.** SHA-256 over: `ms` version and git revision of the cranelift fork (`vendor/cranelift-codegen`), ISA triple and flags (`opt_level`, `is_pic`, `regalloc_algorithm`, probestack, frame pointers), `Options::checks` and `poll`, and the CLIF text of the function with every `u0:N` function reference, global value and data reference replaced by the declared symbol name.
- **Value.** Machine code bytes, alignment, relocations as (offset, kind, symbol name, addend), source-location rows as (code offset, file, line, scope-relative scope id). Written to `.ms-cache/obj/<2-hex>/<hash>` by atomic rename; a corrupt entry is a miss.
- **Stable symbol names are the prerequisite.** Today `cg.rs` names non-exported functions `name#{index}`, strings `ms.str.{i}`, and glue and descriptors by queue order, so inserting one function renames the callers' references and every key changes. Names become content-derived: function `name#<hash of module path, name, signature>`, strings by content hash, glue and descriptors by a structural type hash. This also makes Cranelift object output deterministic across edits.
- **Source locations and scopes.** `Lower` interns locations and scopes into global tables (`g.locs`, `g.scopes`, `scope_base`). The cached rows hold file, line and function-relative scope ids; on a hit they are re-interned into the current tables with the new `scope_base`.
- **Whole-build short cut.** After MIR optimize and unwind, hash the module (MIR text plus options plus link inputs). If `.ms-cache/exe/<hash>` exists, copy it to the output. This makes a no-change rebuild skip codegen and link without needing the per-function cache.
- **Eviction.** Entries unused for 30 days are deleted on the next miss-writing build; `ms clean` removes `.ms-cache`. Concurrent builds are safe because writes rename into place.
- **Observability.** `MS_TIMINGS=1` prints phase times and cache hits/misses on stderr (none exists today).
- **Platform parity.** The key includes the target triple; the cache is used on Linux, macOS and Windows. Windows ARM64 COFF keeps its non-PIC rewrite before hashing, so the key sees the final CLIF.
- No source syntax, diagnostics or CLI flags change.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-clif/src/cg.rs`, `lower.rs` | Content-derived symbol names; normalized CLIF hash; hit path through `define_function_bytes`; rows re-interned | Unit: same function hashes equal after unrelated insertions; hit and miss objects link and run identically |
| `crates/ms-clif/src/dwarf.rs`, `llvm_tables.rs` | Unchanged for Cranelift; LLVM path untouched until Stage 3 | Debug line tables and fault traces equal with a warm cache (e2e fault fixture) |
| `crates/ms-build/src/native.rs` | Whole-build key, cache directory, `MS_TIMINGS` | Unit: key changes with options and compiler version |
| `crates/ms-driver`, `ms-cli` | Cache location from the project root; `ms clean` removes it | CLI test |
| `ms-check`, `ms-lower`, `ms-mir`, `ms-rt`, `stdlib/` | Unchanged | none |
| `documentation/contributing`, `wiki/` | Cache layout, key inputs, `MS_TIMINGS` | `make docs-check` |

## Alternatives

- **Do nothing.** Debug builds stay at 8 s per edit on this workload; the comparison is a 0.23 s rebuild in Go. Rejected by the stated priority.
- **Whole-build cache only.** Cheap and safe, but any one-line edit still pays 4.5 s of codegen. Kept as the first step inside this design, not the end state.
- **Per-source-module object files.** Needs cross-object symbol visibility for glue, descriptors and the program tables built from the whole module (`emit_tables`), a larger rewrite of `cg.rs`; per-function granularity reuses the existing single-object structure.
- **Parallel Cranelift.** Independent functions compile in parallel: about 4x on 4 cores for the 4.5 s. Complementary, does not help a one-core CI machine, and can be added later around the same miss path.
- **Cache MIR instead of CLIF.** The key would depend on MIR names and ids that shift on edits; CLIF text after normalization is what the compiler actually consumes.
- Drawbacks: a cache-correctness bug produces a wrong binary silently. Mitigations: key includes the vendored cranelift fork revision; `MS_CACHE=off` disables; CI runs the conformance corpus with a warm cache.

## Staging and verification

1. **Stage 0:** `MS_TIMINGS=1` prints per-phase times (front end, MIR, CLIF lowering, `define_function`, tables/DWARF, link) and, in Stage 2, CLIF-stability across a one-function edit. Gate: `make verify`.
2. **Stage 1:** whole-build short cut. The key hashes: the `ms` executable (build id, not `.msversion`), the final MIR text including file paths and lines, build profile, every codegen-affecting env var (`MS_BACKEND`, `MS_COUNT_STR`, `MS_LLVM_TOOLS`, `MS_RT_HOT`, `MS_VECTORIZE`), the runtime archive bytes (`MS_RT_LIB` override included), `--link` inputs, the working directory (baked into DWARF `comp_dir`), and the target. Entries hold the executable and its debug companion. `MS_CACHE=off` disables, `MS_CACHE=verify` rebuilds and compares. Measured (Debug, 4 cores, 122k lines, 12,006 functions): 8.2 s cold, 3.0 s no-change rebuild (front end 2.6 s, cache key 0.4 s). The key prints and hashes the canonical MIR text; the 1 s gate was unreachable while the front end runs (check alone is 1.8 s) and is replaced by this floor. `MS_CACHE=verify` passed on the workload. Not yet run: the conformance corpus under a warm cache.
3. **Stage 2:** parallel Cranelift: lower serially (it mutates shared tables), then `define_function` across cores and `define_function_bytes` in order. No correctness risk from keys. Measured (Debug, 4 cores, same workload): 8.6 s -> 6.1 s, executable byte-identical to the serial build. Lowering (0.5 s), glue, tables and DWARF stay serial, which bounds the gain.
4. **Stage 3, decided only after Stage 0 numbers:** per-function cache as designed above. Review found it needs source-location rows stored relative to the function start and rebased on a hit (`set_srcloc` bits index a global table), scope tables rebased the same way, content-derived names for globals, vtables, unit blocks and glue (with collision-free identity such as body hash), a key that includes the `ms` binary hash and the module-wide single-pass register-allocator choice, and the key computed inside `define_with` after the Windows ARM64 rewrite and `spill_loop_cold`. Its floor is front end (about 2.7 s) + lowering (0.5 s) + tables/DWARF + link, so 3.5 s is the best case, not 0.23 s. Build it only if Stage 2 leaves more than 2 s of `define_function` on the edit-one-function case.
5. **Stage 4 (not decided here):** partition the LLVM IR by module, `opt` + `llc` in parallel, cache each; costs cross-partition inlining and a rewrite of the single-section text anchor in `llvm_tables.rs`. Needs its own runtime-regression measurement on `bench/perf`.

Release builds get nothing from Stages 0 to 3 beyond the no-change short cut; the 293 s LLVM stage is Stage 4.

## Review

Skeptical review, 2026-10-31: build with changes. Adopted: Stage 1 key inputs (binary hash, runtime archive, env vars, cwd, companion), parallel Cranelift ahead of the function cache, per-function cache gated on measurement and corrected for srcloc and scope handling, stable-name inventory, floor-based gate. The earlier 3.5 s gate was unreachable and is withdrawn. The 11.1 s vs 8.0 s first and second runs are one cold-file-cache effect or noise; Stage 0 reports repeated runs.

## Open questions

None that change the language or user-visible behavior; cache location defaults to `.ms-cache` beside `ms.toml`, which already exists.
