# Incremental checking

## Summary

- Problem: after an edit, the language server re-parses and re-checks every module of the project, so cost grows with project size (0.44 to 0.6 ms per module in a warm session).
- Finding: no real project reaches the cost where this matters. Warm body-edit re-checks measure 7 to 48 ms, against a 100 ms gate. Stage 0 is done and the proposal is parked.
- Decision requested: none now. Reopen if a real project passes the gate. The first fix for users and agents is the fixed standard-library floor of a fresh process (separate proposal).

## Status

Parked at Stage 0, 2026-11-15, checked against `7d4b8c2f`. Direction (lead): Stage 0 only; build Stage 1 only if a real, non-generated project has a median body-edit re-check over 100 ms in the language server. Owner rule: no caches until a redesign cannot match them (`checker-type-interning.md`). Review outcome: pending.

## Problem

`ms check` and `ms build` are fresh processes, which this cannot speed up. Only the language server keeps a `Session`, so it is the only beneficiary. It keeps a result only for graphs that never read the changed file (`invalidate_document`, `ms-lsp/src/server.rs`); an import chain always misses.

Stage 0 measurements. Harness: a throwaway `crates/ms-lsp/examples/replay.rs` (not committed) calls `analyze_options` with one shared `Session`, alternating a one-literal body edit, 15 times, median. Release `ms`, 4 cores, `7d4b8c2f`.

| Project | Lines | Modules | Warm body-edit re-check |
| --- | --- | --- | --- |
| `tools/conform.ms` (+ `lib.ms`) | 109+ | 2 | 7.0 ms |
| `bench/agent/report.ms` | 141+ | 5 | 30.7 ms |
| `stdlib/data/html.ms` (largest stdlib file, as a file) | 5053 | 1 | 33.5 ms |
| largest agent-written program in `bench/agent/results/sources` | 2579 | 1 | 48.3 ms (52 diagnostics, so ownership is skipped: an underestimate) |
| generated, chain imports (not a gate input) | 10.8k / 43k | 200 / 800 | 89 / 479 ms |
| hello | 3 | 1 | 1.3 ms |

- No real project reaches 100 ms. The gate fails, so Stage 1 is not built. The 800-module generated project is not a gate input.
- Cheap alternatives, measured. Skipping the fixed standard-library setup in a live server: already done by the shared `Session` (hello is 96 ms cold, 1.3 ms warm). Skipping re-parse of unchanged files: parse is about 7% of a project check (callgrind: 37M of 520M instructions on the 200-module project), so about 6 ms of 89.
- A fresh process pays 46 ms for hello. That is `ensure_standard` (15% at 200 modules, 35% of hello) and bundled body checks. It helps every `ms check` and every agent, and is the next proposal.

## Design (if the gate is ever passed)

One rule: **a module's result is a function of its text and the interfaces of what it imports, so an edit re-runs a module only when its text or an imported interface changed.**

- Flat tables indexed by `ModId(u32)`: `text_version`, import adjacency in CSR plus its transpose, per-module diagnostics, and an interface record (exported names and kinds, signatures as `TyId`s from `tytable.rs`, type definitions and fields, impl set, omittable parameters, constant types). Early cutoff compares the new record with the old one for equality. No hash.
- Phases split at `check_module` (`checker.rs:689`): interface (`import_symbols` through `implementation`), then bodies (`check_defaults`, `check_bodies`, `declaration_checks`).

How a body reaches an importer, and the coverage of each:

| Path | Where | Covered by |
| --- | --- | --- |
| Inferred effects | `effects.rs`, `effect_reach.rs` | Re-scan changed callables, propagate on reverse edges while summaries change; not in the interface record |
| Ownership summaries | `ownership/modes.rs` (`Summaries.reads`) | Re-analyze changed callables and readers whose read summary changed |
| Generic bodies | checked once with bounds; instantiated at lowering (`ms-lower`) | Check unaffected; lowering reads the new body, and it is not part of checking |
| Constant values | `constants.rs` (uses check as a call), `constfaults.rs` | Constant type in the interface record; value is read at use by lowering and folding, so a constant edit re-checks importers that use it |
| Default arguments | `ParameterDefaults` (`types.rs:95`) holds only omittable names | Names in the interface record; default expressions are checked in their own module |
| Inferred result types | none: a named function's result type is mandatory (`ast.rs:138`) | Nothing needed (an unannotated constant is above) |
| Unused bindings | `unused.rs` is per module, local bindings only | Per module |
| Global method clashes | `add_method`, `contracts.rs:512` | Impl set in the interface record; a clash re-checks the impls of both modules |
| `finite_applications`, `finite_type_applications` | `recursion.rs:199`, `:371` | Whole program over generic bodies; stays global until measured |

Hazard found: ownership and effect tables are keyed by `(file, NodeId)` (`ownership/modes.rs:120`, `constfaults.rs`), and a reparse renumbers nodes. Callable identity must become the declaration index in its module.

Pointers that outlive a module's check: every importer expression fact holds a `Ty` whose `def` is the declaring module's `Rc<Definition>` (`types.rs:336`); importers copy `SymRef`s into their name tables; `Program::methods` holds `MethodRef`s with `DeclRef`; `Program::symbols`, effect nodes and the language server's occurrence index hold `ModRef`. That is six families and the first scales with every importer fact, so it is not small. In-place patching of symbol cells is rejected. If this is built, importers hold `TyId` and `(ModId, decl index)` into the flat tables, which also serves lazy standard-library declarations.

## Components touched

Unchanged until the gate is passed. If built: `ms-driver` (`ModId` tables, reparse), `ms-check` (phase split, interface record, callable identity), `ms-lsp` (patch the session), `bench/perf/compile` (edit-replay harness in `.ms`).

## Alternatives

- Do nothing: wins on the evidence above.
- Skip re-parse of unchanged files: about 7%, cheap, and the first step if anything is done.
- Result cache keyed by hashed inputs, in memory or on disk: a cache by another name; an on-disk form needs a serialization of the `Rc` type graph (`analyze-the-standard-library-on-demand.md`).
- A query framework: a new dependency; this needs two edges and one record per module.
- Parallel checking: the checker is `Rc`-based.

## Stages

0. Done: the table above. The harness stays out of the tree until a later stage needs it.
1. Gated. Index design: callable identity, interface record, `ModId` tables. Output byte-identical.
2. and 3. Patch on edit and early cutoff, ship as one PR.

Gate for every stage after 0: the differential test. For each conformance fixture, apply random edits (body, signature, add or remove import, delete a module, syntax error and repair) and compare incremental diagnostics, emitted MIR and `ms inspect` effects with a from-scratch check. The edit set must include edits that change an effect or an ownership summary without changing a signature (a body starts calling `print`; a body starts moving a parameter).

## Open questions

None that change the language or user-visible behavior.
