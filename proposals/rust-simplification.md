# Simplify the Rust crates and runtime

## Summary

- The Rust tree is 257k lines in 37 crates. Size is not the problem; four structural causes make it hard to read: std knowledge inside the compiler, one-giant-function dispatchers, two backends that each walk all of MIR, and a runtime of monolith files with no internal layering.
- Change: four independent tracks, each shippable alone, each gated by a before/after measurement. No language, grammar, ABI or user-visible change.
- Decision requested: approve the tracks and their order (Open questions). Nothing is implemented by this document.

## Status

Proposal, 2026-11-06, checked against `92f810ad`. Not implemented. Builds on, and does not repeat, `lowering-stdlib-boundary.md`, `compiler-session.md`, `runtime-abi-trim.md` and the crate consolidation recorded in the project folder (`crate-consolidation-proposal.md`: tools and runtime folds shipped, the std fold rejected on a 12 s vs 1.5 s incremental build). Numbers below are line counts from the tree; anything not measured is marked "hypothesis".

## Problem (measured)

1. **Std knowledge in lowering.** `ms-lower` is 25.2k lines; 11.5k are in files that special-case library behavior: `native.rs` 3589, `json.rs` 1897, `rtcall.rs` 1397, `mapset.rs` 1055, `natiface.rs` 674, `text.rs` 668, `external.rs` 541, plus `iterate`, `httpserve`, `fsinfo`, `fswalk`, `mathops`. `native.rs` alone has ~300 string-keyed arms and `STRING_TO_STRING`/`PLAIN_STRING` name tables, the "Rust name lists" the owner rules forbid. Adding a std function touches `.ms`, an `ms-std-*` crate, and one to three lowering sites nothing connects.
2. **Giant dispatchers.** 41 functions exceed 200 lines (170 exceed 100) among 8.8k. The worst: `ms-clif/lower.rs::lower_inst` 1051, `ms-mir/verify.rs::check_types` 896, `ms-mir/interp.rs::step` 640, `ms-mir/parse.rs::parse_module` 428 and `parse_line` 400, `ms-check/contracts.rs::implementation` 421, `ms-lower/native.rs::native_method_tail` 360. Each is a `match` over ~105 `Op` variants (`ir.rs`, 300 lines) repeated per consumer, so adding or changing an op means editing up to eight places (ir, builder, verify, interp, parse, print, clif, llvm).
3. **Two backends, each a full MIR walker.** `ms-clif` holds `lower.rs` 3656 + `cg.rs` 1563 (Cranelift) and `llvm_ir.rs` 2410 + `llvm_tables.rs` 542 (LLVM). Each re-implements op semantics (checked arithmetic, string and optional ops, calls into the runtime). Semantic drift between debug (Cranelift) and release (LLVM) is a correctness risk, not just a reading cost (hypothesis: a differential test over the conformance corpus would show current mismatches; not yet run).
4. **Runtime without internal layering.** `ms-rt` is 32k lines and 2356 `unsafe` mentions in 44 files; `task.rs` 3437, `string.rs` 3020, `vec.rs` 2671, `fault.rs` 2550, `map.rs` 2484, `promise.rs` 2022 mix primitives, ABI shims (`#[no_mangle]`) and policy in one file. Platform splits are file-pair (`sys`/`sys_windows`, `trap`/`trap_windows`) rather than behind one trait. 30 `static mut`/atomic statics and the `ms-rt-hot` pure/stateful rule exist but are enforced by comment only.
5. **Ownership logic is spread over two crates.** `ms-check/src/ownership/walk.rs` is 5079 lines (largest file in the repo); the MIR `lastuse`, `copyelim`, `optparam` passes re-derive related facts. `mir-ownership-pass-scaling.md` already shows the cost.

## Design: four tracks

**A. Finish the std/compiler boundary (largest win; extends `lowering-stdlib-boundary.md`).** Target: `ms-lower` has no file named for a std module, and no string tables of std method names. Mechanism: classify each remaining hand-lowered entry as (a) language-level (typed JSON, `Map`/`List`/`Optional` natives, `panic`: stays, but dispatches by a declared `// ms:` attribute on the `extern fn`, not by name list), or (b) library (moves to `.ms` over plain externs, as `random`/`html/parse` already did). `STRING_TO_STRING`/`PLAIN_STRING`-style tables are replaced by reading the declared signature through `rtcall.rs`, which already marshals from `rt_symbols`. Gate: line count of `ms-lower` drops, conformance and e2e unchanged, `bench/perf` within noise.

**B. One op table drives every MIR consumer.** Replace the repeated `match` over `Op` with a declarative description per op (operand/result kinds, effects, verify rule, text name), expanded by a `macro_rules!` in `ms-mir` (no new dependency) into the printer, parser, verifier signature check and effect queries. Codegen and interpreter keep their own semantics but dispatch through small per-family functions (`arith`, `string`, `optional`, `call`, `mem`) instead of one 1000-line function. Gate: `ms mir` text round-trip tests, verifier corpus, no codegen diff (compare emitted object files byte for byte on the conformance corpus where deterministic).

**C. Shrink the backend duplication.** Do not delete either backend (Cranelift is the fast debug path; LLVM is the release path). First add a differential test running the conformance corpus through both and comparing output, to measure drift. Then move op semantics that are not target specific (overflow-check shape, string/optional layout accessors, runtime call signatures) into a shared `ms-clif/src/abi_ops.rs` that both emit from. Hypothesis, to be confirmed by the differential run, before deciding whether to go further: a single `Emit` trait with Cranelift and LLVM implementors. Overlaps the "LLVM compile speed" thread; coordinate before touching `llvm_ir.rs`.

**D. Layer the runtime inside `ms-rt`.** Split by responsibility into directories: `ms-rt/src/{core,data,sched,sys}`: `core` (alloc, fault, desc, cells), `data` (string, vec, map, tree: pure operations separated from the `msrt_*` export shims), `sched` (task, promise, poller, pipe, cancel), `sys` (one `Platform` module with `unix` and `windows` backends behind identical function names, replacing the `_windows` file pairs). Pure data operations that satisfy the `ms-rt-hot` rule move there so the rule is a directory, not a comment, and a `repo-check` rule rejects statics in the pure directory. No file over about 1500 lines. Pure moves first (`git mv`, no logic change), then the shim split. Platform: every step runs the full OS matrix (parity rule). Overlaps stream interface and iterator removal threads in `string/vec/map`; do the pure moves only when those land.

## Evidence for the benefit

- Track A removes a measurable amount: up to the 11.5k lines in std-specific lowering files, minus the language-level residue; each entry deleted is the exact "Manuscript first" move the owner asked for.
- Track B replaces up to 8 hand-kept `match` sites per op; the 41 functions over 200 lines drop to the per-family size (target: none over 300).
- Track C is a measurement first: if the differential run finds no drift and the duplication is only syntactic, stop after the shared ABI helpers.
- Track D is the weakest on hard evidence (reading cost, not a bug count); it ships only if the pure file moves change no performance (`bench/perf` and symbol diff of `libms_native.a` identical).

## Alternatives considered

- **Do nothing.** Zero risk; the std boundary keeps growing, since every std addition currently has a lowering side.
- **Merge crates further.** Rejected already: the std fold cost 12 s incremental vs 1.5 s. The crate count is not the complexity.
- **Delete the LLVM backend.** Loses the release-build speed; owner direction in `DESIGN.md` is maximum native speed.
- **Rewrite the runtime in Manuscript.** Out of scope: stateful runtime is the small-primitive Rust the rules allow. Track A moves what is library into `.ms` already.
- **Proc-macro for the op table.** Needs new dependencies (`syn`); `macro_rules!` avoids that.

## Plan

1. Track A, remaining entries, per `lowering-stdlib-boundary.md` order. Continues in flight; this thread audits what is left and lists it.
2. Track B in one PR (`ir.rs`, builder, verify, parse, print, interp).
3. Track C differential test PR, then a go/no-go on the shared emit layer.
4. Track D pure moves after the stream and iterator threads merge; shim split after.

Each PR follows `skills/create-pr`, measures before/after (build time, `bench/perf`, line counts), updates `crates/DESIGN.md` and `documentation/contributing/architecture.md`, and adds a wiki page for any durable lesson.

## Addendum: domains and the perf guard (2026-11-06, owner direction: domain-driven layers, no perf regression)

Dependency facts from the `Cargo.toml` files and `use` sites:

- **`ms-check` has no public facade.** `lib.rs` exports 28 `pub mod`s (`checker`, `calls`, `stmts`, `exprs`, `hints`, `ownership`, ...); consumers reach into internals: `ms-lower` has 167 `ms_check` references (55 into `hir`), `ms-tooling` 17 files, `ms-lsp` 15. Editor queries (`editor.rs`, `suggestions.rs`) live beside the type checker.
- **`ms-lower` consumes the syntax tree, not just HIR.** 47 `ms_syntax::ast` uses in a pass that should read checked HIR; so a syntax change reaches lowering, and HIR is not the contract.
- **Compiler crates depend on runtime crates.** `ms-lower`, `ms-driver`, `ms-lsp`, `ms-build` depend on `ms-rt`; `ms-lower` on `ms-std-decimal` (one call, `expr.rs:242`, parsing a Decimal literal). The compiler/runtime boundary is a single ABI (`ms-rt-abi` plus the generated `rt_symbols` table); everything else is a leak.
- **`ms-std-*` is acyclic but ad hoc**: `io->fs->path`, `process->fs,io`, `system->process`, `archive,net->core`.

Target bounded contexts, each with one public API and a one-way dependency rule (enforced by `ms-repo-check`, which already holds a layering list):

| Context | Crates | Public contract |
| --- | --- | --- |
| Language front end | `ms-syntax` | AST, `parse`, `format` |
| Semantics | `ms-check` split into `semantics` (resolve, types, contracts, effects, ownership) and `editor` (hints, suggestions, completion) | `Program` + typed HIR + diagnostics |
| Middle end | `ms-lower`, `ms-mir` | HIR in, MIR out; `ms-lower` stops importing `ms_syntax::ast` |
| Back end | `ms-clif` (Cranelift, LLVM), `ms-build` | MIR in, object + link |
| Runtime | `ms-rt-abi`, `ms-rt`, `ms-rt-hot`, `ms-std-*`, `ms-native` | C ABI only; compiler never imports these |
| Tools | `ms-driver`, `ms-tooling`, `ms-lsp`, `ms-cli`, `ms-conform` | consume Semantics API only |

New track **E (boundaries)**, mostly mechanical and low risk to perf because it moves no hot code: (1) a `ms_check::api` facade, then make the 28 modules `pub(crate)`; (2) carry the few AST facts lowering still reads (47 sites) onto HIR nodes; (3) move the Decimal literal parse behind the checker (const-evaluated into HIR) and the `cabi` constants into `ms-rt-abi`, then drop `ms-rt`/`ms-std-decimal` from `ms-lower`, `ms-driver`, `ms-lsp` and `ms-build` (the last two may need a feature split for embedding the archive only); (4) split `editor` out of `ms-check`; (5) repo-check rule for the table above. Order: E before A, because A is easier once lowering reads only HIR.

**Perf guard (applies to every track).** Compile-time and run-time are measured separately, before and after, on the same machine against the latest dated baseline in `bench/perf/` (`baseline-2026-10-28.md`):
1. Run-time: `make` perf target over `bench/perf/*/ms.toml`; a regression above noise (agreed threshold: more than 2% median on any case) blocks the PR. Tracks A, B, C, D are checked against this; track E should show none and is proven by identical emitted objects on the conformance corpus.
2. Compile-time: `ms check` and `ms build` on the standard-library-heavy corpus (the front end is `opt-level = 2` in dev for this reason; a crate split must keep that profile and cross-crate inlining: hot front-end functions get `#[inline]` or stay in-crate, measured).
3. Runtime moves (D): `nm` diff of `libms_native.a` exported symbols must be identical, `ms-rt-hot` inlining unchanged (callgrind instruction counts on the map and string cases).
4. Data layout: any new table (track B op descriptions) is a flat array indexed by the op discriminant, not a hash map, consistent with the data-oriented rule.
5. Results go in a dated `bench/perf` section on the PR, not in prose.

## Open questions

1. Order: E, A, B, C, D (E first, since it makes A easier), or start with D (highest readability, lowest risk)?
   Is the 2% median threshold the right perf gate?
2. Is a differential test between Cranelift and LLVM acceptable in CI time, and which platforms (LLVM is Linux and macOS only)?
3. Accept dropping a track if its measurement does not pay for itself?
