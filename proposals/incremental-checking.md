# Incremental checking

## Summary

- Problem: after any edit, the language server re-parses and re-checks every module of the project. Cost is linear in project size: about 0.6 ms per 54-line module, 163 ms at 200 modules, 555 ms at 800.
- Change: make the checked program a set of flat per-module tables that an edit patches. Re-check the edited module, and re-check an importer only when the edited module's interface changed (early cutoff). No hashed result cache.
- Decision requested: build Stage 0 (measure real projects, no behavior change) now; build Stages 1 to 3 only if the gate in Stages passes.

## Status

Proposal, 2026-11-15, checked against `7d4b8c2f`. Direction (Chinmay): "caching is cope for a slow design" (see `checker-type-interning.md`); caches only when a redesign cannot match them. Review outcome: pending.

## Problem

Measured on `7d4b8c2f`, release `ms`, 4 cores, median of 7 runs, `ms check` of generated projects (module `i` imports `i-1..i-3`; each has a record, one method, 10 functions):

| Project | Time | Instructions |
| --- | --- | --- |
| hello | 46 ms | 168M (PR #3958) |
| 200 modules (10.8k lines) | 163 ms | 687M |
| 800 modules (43k lines) | 555 ms | not run |

Where the 687M goes (callgrind, inclusive): `check_modules` 48% (`check_bodies` 23%), ownership 21%, `ensure_standard` 15% (fixed, paid by hello too), load and parse 13%, effects 8%.

- The language server (`crates/ms-lsp/src/server.rs`, `invalidate_document`) keeps a cached result only for graphs that never read the changed file. A chain of imports always misses, so one edit pays the whole table above.
- `ms check` and `ms build` are one process per run. Nothing here speeds them up; `ms build` already has the mtime short cut (`incremental-builds.md`).
- The cost a fresh process pays before it reads any project code is the 40 ms hello floor. That is lazy declarations of the standard library, a separate proposal that builds on `TyTable`.

## Design

One rule: **a module's result is a function of its text and the interfaces of what it imports, so an edit re-runs only modules whose inputs changed, and stops where an interface is unchanged.**

Data, flat and indexed by `ModId(u32)` (dense, assigned at load):

- `text_version: Vec<u32>`, bumped by the server on `didChange` and by file watches. No source hashing.
- `imports: CSR` (start offsets plus targets) and its transpose, `importers`. Rebuilt only when a module's import list changes.
- `interface_fp: Vec<u64>`: hash of the module's exported surface, canonical in `TyId`s (`tytable.rs`): exported names and kinds, signatures, type definitions and fields, and its impl set (methods are global but visible by import, `contracts.rs:1483`). Bodies are never in it.
- `diagnostics: Vec<Vec<Diagnostic>>` per module; the program's list is their concatenation in module order, so output order is unchanged.
- Facts stay where they are: per-module tables indexed by node id (`syntax.rs`, `Facts`). A re-check clears that module's tables only.

Phases per module, split at the line `check_module` already has (`checker.rs:689`):

1. Parse (`text_version` changed).
2. Interface: `import_symbols` through `implementation`. Compute `interface_fp`.
3. Bodies: `check_defaults`, `check_bodies`, `declaration_checks`, plus the module's ownership, effect and unused results.

Edit flow: parse the module, run its interface phase, compare `interface_fp`. Equal: run bodies of this module only. Different: also re-run interface and bodies of each direct importer; an importer whose own `interface_fp` is unchanged stops the walk there.

Stable symbol slots, the main risk. Importers hold `Rc<Sym>` and `Rc<Definition>` of the old revision. When the set of declared names is unchanged, the new revision writes into the existing symbol cells (`Sym::ty`, `Definition` fields are already `RefCell`) and swaps `decl` to the new syntax, so importers need no pointer fix. When names change, `interface_fp` changes and importers re-import anyway. Stage 1 starts by counting every `Rc` into a module that outlives its check; if an uncovered one exists the design changes before code is written.

Whole-program passes follow the same cut:

- Ownership: `Summaries` and `reads` already record who read which callable's summary. Re-analyze the callables of re-checked modules; re-analyze a reader only if a summary it read changed.
- Effects: `EffectScan` nodes are per callable; re-scan nodes of re-checked modules, then propagate along reverse edges until summaries stop changing.
- `unused::check` and `finish_modules` run per re-checked module. `finite_applications` is whole program; Stage 1 measures it before touching it.

Estimates (hypothesis, to be measured in Stage 0): a body edit costs one module's parse, interface and bodies (about 0.4 ms from the table) plus O(modules) bookkeeping at roughly 1 to 3 us per module. So about 1 ms at 200 modules and 3 ms at 800, 150x and 180x faster. A signature edit also re-checks direct importers, about 4 modules, so 2 to 5 ms.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-driver/src/load.rs`, `compile.rs` | `ModId` tables, reparse changed modules only, graph patch | unit: import add and remove patch the CSR |
| `ms-check/src/checker.rs`, `syntax.rs` | interface and body split, per-module diagnostics, stable symbol slots, `interface_fp` | differential test below |
| `ms-check/src/ownership`, `effects.rs`, `unused.rs` | re-run from changed callables with summary cutoff | differential test |
| `ms-lsp/src/server.rs`, `analysis.rs` | patch the session instead of `cache.clear()` | LSP edit-replay test |
| `bench/perf/compile` | project generator in `.ms`, edit-replay timings | dated result |
| `ms-cli`, `ms-lower`, `ms-build` | unchanged | |

## Alternatives

- Do nothing: costs 0.6 ms per module per edit. Current real projects are small (`tools/conform.ms` checks in 86 ms), so today's gain is smaller than the generated numbers; the do-nothing case wins until a real project passes the gate.
- Keep the whole-result reuse (today): helps only graphs that never read the edited file; imports chains always miss.
- Result cache keyed by hashed inputs, in memory or on disk: a cache by another name, and an on-disk form needs a serialization of the `Rc` type graph, which `analyze-the-standard-library-on-demand.md` already rejected.
- A generic query framework (salsa-style): a new dependency and memo tables of closures; this design needs only two edges and one fingerprint per module.
- Parallel checking: the checker is `Rc`-based; it would not reduce work.

## Stages

0. Measure: the generator, edit-replay through the language server (comment, body, signature, new import), and real project sizes from `bench/agent`. Gate: build Stage 1 only if the median body-edit re-check of a real project is over 100 ms, or the 800-module replay is the shape users reach. No behavior change.
1. Symbol-slot audit, interface and body split, `interface_fp`, per-module diagnostics. Still re-checks everything; output byte-identical. Check: conformance corpus unchanged.
2. Patch on edit in the checker for body-only edits and the language server. Check: differential test, plus the replay timings.
3. Interface-change cutoff, ownership and effects summary cutoff.

Each stage is one PR; Stage 2 and 3 report the replay numbers against the Stage 0 baseline. Platform parity: no platform-specific code; replay runs on all six scheduled platforms.

## Verification

- Differential: for each conformance fixture and project, apply a random sequence of edits (body, signature, add or remove import, delete a module, syntax error and repair). After each edit the incremental diagnostics, emitted MIR and `ms inspect` effects must equal a from-scratch check. A mismatch fails the test; this is the gate that matters, since a wrong incremental result is worse than a slow one.
- Timing: instruction counts (callgrind) for one edit, and median of many runs for the server loop, per `perf-bash`.

## Open questions

None that change the language or user-visible behavior.
