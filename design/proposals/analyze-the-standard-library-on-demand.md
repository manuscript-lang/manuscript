# Analyze the standard library on demand

## Summary

- Problem: every `ms check`, `run` and `build` runs the effect scan and the ownership analysis over every callable of every bundled source module the program imports, though only the few the program reaches matter. A hello program pays for 508 callables in 25 modules.
- Change: scan and analyze a bundled callable only when something asks for it: the effect scan from the project's own callables along their edges, the ownership analysis from lowering, which asks for each callable it lowers.
- Decision requested: build it in two steps (effects, then ownership), in `ms-check` and `ms-lower`. No language or output change.

## Status

Evidence measured 2026-11-14 on `main` a8deb279 (release `ms`, callgrind, `ms check` of a one-line `print` program). Implemented 2026-11-14: hello `ms check` 317.5M to 167.7M instructions, `tools/conform.ms` 846M to 363M (`bench/perf/compile`). Skeptical review: the independence claim holds; build with three changes (the lowering hook sits at the callee reads, effects scan every reached node before propagating, measure `ms build` and a larger program first); applied below.

## Problem

`ms check h.ms` (hello) takes 317.5M instructions (about 70 ms). Inclusive costs: `ensure_standard` 34% (parse and declarations of the eager modules), `ensure_source` 44% (checking the 15 source modules `print` reaches through `core.ms`), `Hir::ownership` 23%, `effects::Scan` 18%, `check_bodies` 13%, `malloc` and `free` about 22% of the total as self cost.

The two program-wide analyses have no reason to cover the whole library:

- `effect_summaries` (`crates/ms-check/src/effects.rs`) scans every function, type and constant of every loaded module and every method, then propagates. Its consumers are the effect violations of project callables (`effect_violations`, `declared_effects`) and tooling (`inspect`, lint, guide pages). A bundled callable matters only if a project callable reaches it.
- `Hir::ownership` (`crates/ms-check/src/ownership/mod.rs`) analyzes `callables()` of every module in the program, to a fixpoint with summaries. Its diagnostics concern project code; the standard library is validated when it is built. Lowering (`ms-lower`) is already demand driven (`function_for` and `drain` lower only what `main` reaches), so it reads facts for a small part of what was computed.

Ceiling, measured with throwaway patches (wrong for builds, so only a bound): scanning effects only from project callables along their edges takes hello from 317.5M to 253.9M (-20%). Also analyzing ownership only for project callables takes it to 180.9M (-43%).

## Design

The standard library does not depend on the program, so a bundled callable's analysis is a function of the library alone; analyzing it later gives the same result as analyzing it first. That makes demand-driven analysis equal to the whole-program one for every callable it covers.

1. Effects. `effect_summaries` starts from the project nodes and scans a bundled node when an edge first names it, with a work list that also follows interface-conversion edges; every reached node is scanned before `propagate_effects` runs, because an edge to an unscanned node would turn into `unknown`; `declared_effects` runs over the scanned nodes. A callable never reached has no entry in `Program::effects`. Tooling that lists the effects of library items (`inspect`, guide pages, the golden listing test) asks for the full scan through one option on `CheckOptions`, which keeps the present behavior for it.
2. Ownership. The round loop in `Hir::ownership` starts with the project callables. After each analysis, the callee summaries it read (`reads`, already tracked) name callables not yet analyzed; they join the set and run in the next round, until the set stops growing. The result is an `Ownership` over that set plus an engine that can extend it (the classifier, summaries, escaped lambdas and the contract methods stay alive in it).
3. Lowering. Lowering reads a callee's facts at the call site, not only when it lowers the callee: `owned_mask` reads `moving_params`, and `function_for` reads `ReturnsBorrow` and `ReturnsView` when the job is requested. The engine is therefore asked in `function_for` and `owned_mask`, before those reads, to extend the tables to that callable and whatever its summaries read; `Cx` holds the engine and the extended `OwnershipFacts` behind interior mutability instead of sharing an immutable `Rc`. Calls through an interface or a generic bound resolve to an implementation only at lowering, so the engine, not a static edge scan, covers them. A late-joining callee is sound because a summary read of a callable not yet analyzed is recorded as a read (`Summaries::get`).
4. Tooling and tests that read the ownership of every library callable call the engine with all callables.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/src/effects.rs` | reach-driven scan; full scan on an option | unit: a project function reaching one library function scans only that chain; golden listing unchanged |
| `ms-check/src/ownership/mod.rs` | closure of reads; an engine that extends the tables | unit: extending one callable equals the whole-program result for it; a library cycle |
| `ms-check/src/lib.rs`, `checker.rs` | the engine in `Program`, the option | existing |
| `ms-lower/src/func.rs`, `cx.rs` | `Cx` owns the facts and extends them before a bundled callable | conformance corpus, both backends |
| `bench/perf/compile` (new) | `ms check` and `ms build` of hello, instructions and median time | dated result |

## Alternatives

- Do nothing: every compile and every conformance fixture pays about 130M instructions for analyses nobody reads. CI cost scales with it (each fixture compiles its own program).
- A persistent cache of the checked library on disk: the checker's results are a graph of reference-counted types, interned names and per-module fact tables; a snapshot needs a stable serialization of all of it, an invalidation key, and loading it is still proportional to the library. It also hides the same waste behind a cache the first run, a CI runner and a fresh install do not have.
- Check and analyze library bodies lazily as well (the 13% in `check_bodies`, and parsing): a later step. It needs per-function type checking that lowering can trigger, which is a larger change than these two analyses.
- Memoize the library analysis once per `Session`, as the checked library already is: it helps the language server and any harness that keeps a session, but the CLI makes a new session per process, so a single `ms build` pays in full. Demand-driven analysis helps both and needs no snapshot; a memo can still be added on top for sessions.
- Parallelize the analyses: the checker uses `Rc`, so it cannot cross threads without a rewrite, and the work would remain.

## Risks

- Lowering asks for a fact that was never computed. The engine makes the request itself, so a callable lowering reaches is analyzed before it is read; a debug assertion in the table getters (missing callable) catches a path that skips it.
- Round count: the whole-program loop allows `callables + 16` rounds; the closure keeps the same bound per set.
- Effects of an unreached callable are absent, not "unknown"; consumers that list them use the full option.

## Verification

Measure `ms build` (Debug and Release) and a larger program before building, not only `ms check` of hello; the ceiling shrinks as lowering and code generation grow. `make conform` and `make conform-llvm` unchanged; the `ms-check` ownership and effects tests; before and after instruction counts of `ms check` and a release `ms build` of hello and of a larger program, against the baseline in `bench/perf/compile`.
