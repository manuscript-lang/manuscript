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

## Addendum: deletions (2026-11-06, owner direction: delete as part of the refactor, not only dead code)

Every track has a deletion budget stated in lines removed; a track that deletes nothing is questioned.

**Dead now (script-found, to be confirmed per symbol by removal plus a green build):**
- 25 `pub`/`pub(crate)` Rust functions named nowhere else in the tree, e.g. `ms-check/types.rs` `id_str`, `is_inferred`, `std_is`, `sub_opt`; `hir.rs` `declaration_parameters`; `ownership/mod.rs` `use_at`; `ms-mir` `verify_func`, `replace_uses`, `is_call_kind`, `is_ref`, `f2i_opt`, `list_drop_last`; `ms-std-json` `object_entries`, `array_push`, `object_add` and two `*_with_capacity`; `ms-std-path/glob.rs` `matches_lenient`; `ms-lsp/text.rs` `end_position`; `ms-tooling/tree.rs` `with_children`.
- About 109 exported `msrt_*`/`msstd_*` functions defined in Rust and referenced by no `.ms` file and no other Rust file: 84 in `ms-rt` (mostly `vec.rs`: `msrt_list_*` and `msrt_bytes_*` that lowering now inlines or builds, plus `string.rs`, `num.rs`, `streams.rs`), 8 in `ms-std-regex` (`split`, `replace_all`, `captures`, ...), 6 in `ms-std-time`, 6 in `ms-std-net` (`*_error_message`), and singles in `fs`, `bigint`, `decimal`. Caveat: names built with `format!` in lowering are invisible to this scan, and the `ms_*_v1` C ABI in `cabi.rs` is public and stays. Method: delete a batch, run `cargo xtask symbols`, the build and the e2e/conformance run; anything lowering still needs fails at compile time because `rt_sig` has no symbol.
- 14 `#[allow(dead_code)]` sites: each is either removed with its code or justified.

**Made obsolete by the design (deleted in the same PR as the track):**
- A: the std-specific lowering files and name tables in `ms-lower` (`natiface`, `httpserve`, `fsinfo`, `fswalk`, most of `native.rs`'s string-keyed arms, the five duplicated identity arms in `closure.rs`). Budget: several thousand of the 11.5k lines.
- B: the hand-written per-consumer `Op` matches that the op table replaces (print/parse name tables, verifier arity checks, effect queries); `lower_inst` and `check_types` shrink into family functions.
- C: duplicated op semantics between `lower.rs` and `llvm_ir.rs` after the shared layer; `llvm_tables.rs` if the table can derive from the op table.
- D: the `_windows` file pairs (`sys_windows`, `trap_windows`) folded behind one platform module; the thin `msrt_*` shims that only forward to a safe function.
- E: the `pub mod` surface of `ms-check` (28 modules become `pub(crate)`, which also makes rustc report the unused items inside them), and the `ms-rt`/`ms-std-decimal` edges from compiler crates.
- Test-only code in production crates: `ms-mir` `interp.rs` (1205 lines) is used only by tests (callers are all under `tests/`); move it behind a `test-support` feature or dev crate so the shipped compiler does not carry or compile it. Not a deletion of the oracle.

**Workaround to remove:** `vendor/cranelift-codegen` (7.7 MB, a local patch for `sadd_overflow` flag fusion and an assertion fix). `PATCH.md` states the removal condition (a Cranelift release with the same rules) but I found no tracking issue; file one and check the current upstream release before anything else here. Not verified whether upstream now has the rules.

**Not examined, to check before the plan is final:** `bench/` (71 MB), `tests/` (35 MB), `extensions/vscode`, and `tools/*.ms` for unused fixtures and scripts.

## Addendum: track F, fewer locks in the runtime (2026-11-06, owner direction: remove locks and mutexes so the runtime is faster)

Inventory (`ms-rt`, `ms-rt-hot` and `ms-std-*`, non-test code): no `RwLock`; `Mutex` statics or fields in `isolate.rs` (8), `sched.rs` (5), `alloc.rs` (5), `poller.rs` (4), `streams.rs` (3), `ms-std-net` (6); `Condvar` only in the blocking pool (`glue/pool.rs`). Atomics are already the main mechanism (`sched.rs` 18, `fault.rs` 16, `alloc.rs` 11). The single-thread hot paths are already lock-free: the allocator keeps per-thread heaps with an atomic page table and a remote-free stack (`wiki/runtime/one-process-heap-pages-name-their-owner.md`), and cancellation is one relaxed flag.

Remaining locks are all on cross-thread paths:

| Lock | Where | Used for | Cost model |
| --- | --- | --- | --- |
| per-thread `mail: Mutex<Mail>` | `sched.rs:137` | posting a wake or event to another thread's scheduler; the owner drains it every loop | taken by every cross-thread post and every poll of the owner |
| `REGISTRY`, `IDLE`, `MAIN_INBOX`, per-inbox `posts`/`wake` | `isolate.rs` | isolate lifecycle and cross-isolate posts | one lock per post, plus a registry lock to find the target |
| `POOL` + two `Condvar`s | `glue/pool.rs` | blocking thread pool job queue | a lock per job submit and take; a condvar wake per job |
| `SHARED` | `alloc.rs:73` | freed large blocks for threads without an arena | a lock per large free or alloc by a pool thread |
| `COMMIT_LOCK`, `IDLE` heaps | `alloc.rs:233,244` | growing the reservation, recycling heaps | only on thread start or heap growth (cold) |
| `HANDLES` | `sched.rs:166` | join handles at shutdown | cold |
| `ms-std-net` server/connection state | `http/server.rs` and others | listener and connection tables | measure |

Honest expectation: an uncontended `std::sync::Mutex` is one atomic compare-exchange on Linux (futex based), so replacing a lock helps only where there is contention or a syscall (a `Condvar` wake). Single-threaded programs will not move. The likely wins are the multi-threaded cases: cross-thread promise wakes, the HTTP server across cores (`proposals/http-server-multicore.md`), and file work through the pool. This is a hypothesis; the first step measures it.

Design (std only, no new crate):
1. **Measure first.** Count lock acquisitions and contended waits per benchmark (a debug counter behind a cfg, not shipped) on `bench/perf` cases that cross threads and on the HTTP multicore bench; a perf lock-contention profile (`perf record` plus the futex wait symbols). Drop any lock that shows under 1% of the run.
2. **Mailboxes (`sched.rs`, `isolate.rs`).** Replace `Mutex<Mail>` with a multi-producer single-consumer intrusive list: producers push with one `compare_exchange` on an `AtomicPtr` head, the owner swaps the head to null and reverses the list (the standard Treiber MPSC pattern, already how the allocator's remote-free stack works). Messages are fixed-size slots from the existing allocator. The `signalled` flag stays the wake gate.
3. **Registry (`isolate.rs`).** The registry is read on every post and written on isolate start and end. Use a fixed array of atomic slot words (flat array indexed by isolate id, per the data-oriented rule) with a generation in the upper bits, so lookup is one load and no lock; creation and retirement use a compare-exchange on the slot.
4. **Pool queue (`glue/pool.rs`).** Keep a parking primitive (futex or condvar) only for idle workers; move the job queue to a lock-free MPMC ring or per-worker deques so submit and take do not contend. Measure against the current single queue before keeping the added complexity (a cache must beat a redesign; here the redesign is the lock removal).
5. **Large-block cache (`alloc.rs`).** Per-size atomic free stacks (the same remote-free stack type) replace `SHARED`.
6. **Leave cold locks.** `COMMIT_LOCK`, `HANDLES` and heap recycling run once per thread or growth step; converting them adds risk and no speed.
7. **Rule, enforced.** A `repo-check` rule lists the allowed lock sites (cold ones above); a new `Mutex` in `ms-rt` outside the list fails the check, with the reason recorded beside the entry.

Gates: the `bench/perf` suite within the 2% rule on single-thread cases, a measured improvement (or the change is dropped) on the cross-thread cases; the existing concurrency tests (`model_tests.rs`) plus a stress test that posts from N threads and checks every message arrives once; the full OS matrix, since memory-ordering bugs are platform-sensitive (Windows and macOS in particular; weaker ordering is fine on x86 and fails on Apple silicon). Each lock-free structure carries its ordering argument in a comment, and every `Ordering::SeqCst` kept is justified.

Risks: lock-free code is harder to read, which cuts against the goal of this proposal; mitigated by one shared MPSC type used in three places instead of three ad hoc versions, and by keeping the lock where measurement shows no contention. Overlaps the concurrency threads (`promises`, `http-server-multicore`); coordinate before editing `sched.rs`, `isolate.rs` or the pool.

## Open questions

1. Order: E, A, B, C, D, with F (locks) after its measurement step, which can run in parallel with E and does not edit shared files, (E first, since it makes A easier), or start with D (highest readability, lowest risk)?
   Is the 2% median threshold the right perf gate?
2. Is a differential test between Cranelift and LLVM acceptable in CI time, and which platforms (LLVM is Linux and macOS only)?
3. Accept dropping a track if its measurement does not pay for itself?
