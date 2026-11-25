# Proposal: incremental builds (code generation cache)

## Summary

- After a one-line edit, `ms build` redoes everything: 5.6 s Debug and 37 s Release on a 122k-line, 1,000-file project (Go: 0.23 s).
- Change: cache backend output by a hash of the exact input the backend consumes. Stage 2 caches Cranelift `define_function` (Debug, 52% of wall); Stage 3 caches LLVM units (Release, 91% of wall) and only starts after a measured gate, because LLVM unit text is not stable today.
- The cache is sound because the key is the whole input; stale output needs a missing key input, which `MS_CACHE=verify` and CI check.
- Decision requested: build Stages 0 to 2 now; Stage 3 is decided from Stage 0 numbers. The 2.3 s front end stays uncached.

## Status

Proposal, 2026-11-16, checked against `9f09fd55`. Supersedes the earlier mtime whole-build cache (removed in #4200: it helped only an unchanged rebuild) and the dropped per-function cache. Direction (Chinmay): "we should do it properly with incremental cache, only then its useful". Reverses the earlier "no hash" choice, which was made for a whole-build key; here the hash covers backend text (measured below). Independent skeptical review done 2026-11-16; its findings (unit count cap, per-unit metadata, Cranelift key and side effects, name collisions, gates) are applied below.

## Problem

Measured on 4 cores, `bench/perf/tools/compile_time.ms` workload (40 packages, 1,000 files, 12k functions), release `ms` of `9f09fd55`, `MS_TIMINGS=1`, second run:

| Phase | Debug | Release |
| --- | --- | --- |
| Check + lower to MIR | 2.3 s | 2.4 s |
| MIR optimize | 0.2 s | 0.8 s |
| Backend (Cranelift on 4 threads / `opt` + `llc` in 4 units) | 2.9 s (6.5 s CPU) | 33.8 s (about 100 s CPU) |
| Link | 0.1 s | 0.1 s |
| Total | 5.6 s | 37.2 s |

- The backend is 52% (Debug) and 91% (Release) of wall time, so caching it removes most of an edit's cost. An earlier spike (`design/proposals/workspaces.md`) measured 20% on a smaller project; here codegen is the larger share and the spike did not cover Release.
- The inputs are unstable. Editing one constant in `pkg20/f10.ms` changed 1 of 4 LLVM units (2 lines); adding a statement and a function changed all four (170k to 590k diff lines each). Causes: `state.rs` names private functions `name#<index>`; `finish_units` cuts by cumulative weight in call order; every unit carries whole-program debug metadata (`!N` ids in emission order), the struct table and, in unit 0, all data (`llvm_ir.rs:690-890`).
- LLVM unit count is capped at the core count (`program.rs:25`), so one recompiled unit costs about 100 s CPU / 4 = 25 s. Release only gets fast with many more units, which costs inlining (`program.rs:15`: 15% slower at four units on a small program).
- Cranelift names private functions `name#<identity_hash>` (32 bits, `.k` suffix on a collision in call order; `cg.rs:170-210`), so names are mostly stable.

## Design

One rule: **backend output is a pure function of the input the backend consumes, the target and the tool; cache it by a hash of exactly that.**

- **Key.** 128-bit hash (two independent 64-bit lanes, in-house, no dependency; a local cache, so accidental collisions only, not an adversary) over: `ms` version, target triple, the full `BuildOptions` debug text (covers the `MS_*` codegen variables), ISA flags, Cranelift fork revision or LLVM tool identity, then the input.
- **Cranelift (Stage 2).** Lowering to CLIF still runs, so strings, data, glue and tables are produced as today. Only `define_function` is skipped. Input: the function's CLIF text with every function, global and data reference replaced by its symbol name and source locations made function-relative. Value: code bytes, alignment, relocations by symbol name, line rows; a hit re-interns rows into `g.locs`/`g.scopes` (shifting scope parents by `scope_base`) and calls `define_function_bytes`. Name instability only causes a miss.
- **LLVM (Stage 3, gated).** Input: the unit's IR text; value: the object. Needs, each measured first: per-unit metadata and type tables with local ids; hash-based private names; unit boundaries that survive an edit (content-defined cuts or hash buckets by module, compared); a unit count above the core count, with its runtime cost on `bench/perf`. Small-callee copies (`write_small_copies`) are in the text, so they are in the key and fan an edit out to the units that copy it.
- **Storage.** `.ms-cache/obj/<2 hex>/<key>`, atomic rename; an unreadable or truncated entry is a miss. Bounded to 256 MiB; a build that stores entries evicts least recently used down to the bound; a hit touches its file and ignores a touch failure. A read-only cache directory turns the cache off for that build. `ms clean` removes it. Windows and macOS use the same code (no hardlinks or locks); a rename that finds the entry present counts as stored.
- **Controls.** `MS_CACHE=off`; `MS_CACHE=verify` compiles anyway and fails on a byte difference; `MS_TIMINGS=1` adds hits and misses. CI runs the conformance corpus once warm under `verify` (nightly, not on pull requests, for the time budget).
- No language, diagnostic or flag changes.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-clif` (`cg.rs`, `lower.rs`) | CLIF key with symbolic references, hit path, relative line rows | Hit and miss link to a byte-identical executable; fault trace and line table equal; every `Gen` table `define_function` touches is restored on a hit |
| `ms-build` (new `cache.rs`, `native.rs`) | Hash, store, evict, read-only fallback, `MS_CACHE`, timings | Unit: key changes with each input; eviction bound; corrupt entry; read-only directory |
| `ms-mir-llvm`, `ms-build/llvm` | Stage 3 only: per-unit metadata, names, cuts, unit cache | Stage 3 gates |
| `ms-cli`, `ms-driver` | Cache location, `ms clean` | CLI test |
| `bench/perf/compile-time/`, `crates/DESIGN.md`, `documentation/contributing/`, `design/wiki/` | Edit-scenario benchmark; cache layout and key inputs | `make docs-check` |

## Alternatives

- **Do nothing.** Every edit pays 5.6 s Debug. The cache costs a hash pass, a store and an eviction policy; the Debug backend is 2.9 s of that, so the most it can save is about 45% of an edit.
- **Cheaper first: raise parallelism or parallelize the front end.** Cranelift already uses all cores; one-core CI and the front end (2.3 s) do not benefit, and neither removes work.
- **Whole-build mtime cache.** Removed in #4200; one edit invalidates it.
- **Cache MIR or the checker.** Larger win but whole-program passes cross modules; Stage 4.
- **Per-function Cranelift cache keyed on MIR.** Needs layout facts and callee identities in the key; CLIF text is what Cranelift actually consumes.
- Risk: a key that omits an input gives a wrong binary silently; see Controls.

## Stages

0. **Measure.** `bench/perf/compile-time/incremental.ms`: cold, no change, edit a body, add a statement, add a function, edit a widely imported module, on the generated workload and on a real project (the repository's `.ms` tools); several runs; per-phase time, Cranelift keys changed, LLVM units changed and how much of the diff is metadata, names or boundaries. Dated results page.
1. **Cranelift key stability.** 64-bit identity hash and deterministic collision suffix; test that an unrelated edit leaves other functions' keys unchanged. Gate: scenarios change only the edited function's key.
2. **Cranelift function cache** with eviction. Gate: one-edit Debug at most 3.5 s here (floor: front end 2.3 s, MIR 0.2 s, lowering about 0.5 s, plus the edited function); executable byte-identical with cache on, off and `verify`; cold Debug within 3%.
3. **LLVM unit cache.** Starts only if Stage 0 shows the prerequisites above reach a one-edit Release rebuild at most 10 s with `bench/perf` runtime within 2% and cold Release within 3%; otherwise record the numbers and stop here.
4. **Front end reuse** (per-module check results), from the remaining 2.3 s; decided after Stage 2.
