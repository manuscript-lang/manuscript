[Wiki](../index.md) › [Compiler and build](index.md)

# Standard-library analyses run on demand

Verified (2026-11-14, release `ms`, callgrind): `ms check` of a one-line `print` program cost 317.5M instructions, 60% of it analysis of bundled source modules the program imports through `core.ms` (508 callables in 25 modules): ownership 23%, the effect scan 18%, body checks 13%. A callable's analysis does not depend on the program that imports it (its facts come from its body and the summaries of what it calls), so the project's callables are analyzed first and a bundled one when something asks.

- Effects: `EffectScan` (`crates/ms-check/src/effects.rs`) registers every callable as a node and scans a node only when a project node or a scanned node reaches it. `Program::effects_of`, `declared_effects_of` and `scan_all_effects` scan the rest when a tool lists library items. An edge to an unscanned node would read as `unknown`, so reached nodes are all scanned before propagation.
- Ownership: `OwnershipEngine` (`crates/ms-check/src/ownership/mod.rs`) starts from the project callables and adds every callable whose summary an analysis reads. It stays in `Program::ownership_shared`. Lowering reads a callee's facts at the call site (`owned_mask`, `ReturnsBorrow`), so `Cx::ensure_ownership` runs in `function_variant`, `owned_mask` and the start of a job; `Cx` owns its facts and absorbs what the engine adds. Interface conversions to a type variable read every implementation's summary, so the engine uses the whole program's methods.
- Result: hello `ms check` 317.5M to 167.7M instructions (-47%), `tools/conform.ms` 846M to 363M (-57%); Debug builds 289 to 185 ms and Release 1072 to 804 ms for `tools/conform.ms` (`bench/perf/compile`).
- Next by profile: `ensure_standard` (parse and declarations of the eager modules, about 35% of what is left) and body checking of the bundled modules.

Apply when: adding a program-wide pass over the checked program, or a tool that reads effects or ownership of library callables (ask per callable, do not read the whole table).
Verify: `demand_analysis` in `crates/ms-check/tests`; `make conform` and `make conform-llvm` unchanged.
