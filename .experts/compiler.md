# Compiler and build lessons

The Go implementation (generated Go, Go runtime, Go toolchain bundling) has been deleted; only the Rust and Cranelift implementation remains. Lessons that were specific to emitting or building Go are gone. What remains is what still constrains checking, lowering, and module loading.

### The implementation is Rust and Cranelift under a value-semantics model

Decision: the compiler, runtime, standard library, and tools use Rust with Cranelift under a value-semantics memory model. Values have one owner and are dropped deterministically; `var` marks mutation, plain values copy, and other values move at their last use into consuming positions. The current contract is in [the design contract](../crates/DESIGN.md) and [ownership notes](../crates/ms-check/OWNERSHIP.md).

Verified: exclusivity must be enforced per borrowing construct and checked with both rejection cases and native execution. Well-formed programs and leak-free happy paths alone do not establish memory safety.

Verified: a local aggregate copy used only for reading can borrow its original when the source stays alive. An intervening write or reference release can invalidate a projection even when it never directly consumes that projection: replacing a parent field may free its old payload. The local copy pass permits string-length caching and additional copies, but otherwise rejects writes and releases during the borrowed span.
Evidence: [local copy elimination](../crates/ms-mir/src/opt/copyelim.rs), [record-copy lifetime regressions](../crates/ms-mir/tests/opt_copyelim.rs), [native payload lifetime checks](../crates/ms-clif/tests/native.rs).
Verify: read-only record iteration loses its deep copy; dropping the source container or replacing its parent field keeps the independent copy.

Apply when: changing ownership, borrowing, drop elaboration, or argument passing in the checker, MIR, or runtime.
Evidence: [ownership corpus](../crates/ms-check/tests/ownership.rs), [ownership notes](../crates/ms-check/OWNERSHIP.md).
Verify: `cargo nextest run -p ms-check`, including the accept and reject ownership fixtures; add the rejected aliasing case before relaxing a rule.

Verified: a closure or method value that changes a mutable alias must retain the owner's storage and the already evaluated path operands. Capturing the leaf copies it; retaining parent-function SSA identifiers is invalid in the child function. A borrowed slot still permits source-call writeback, but the child must not drop its owner. Bound-method writeback must update the current root after the call so a callback's changes to disjoint fields survive.
Evidence: [closure alias regressions](../crates/ms-cli/tests/closure_aliases.rs), [bound alias regressions](../crates/ms-cli/tests/bound_aliases.rs).
Verify: native Debug and Release runs cover indexed/keyed paths, nested callbacks, source/native methods, owned results, and rejected escape/reentry.

### Generic instances resolve contract evidence in the instantiating module

Verified (carried from the retired implementation; the semantics are language rules): a module-local `impl` is visible only in its module, but a generic function from another module is instantiated with the caller's evidence for its bounded type variables, while operations on concrete types inside the body keep the declaring module's choice. A `Map` or `Set` keeps the equality and hashing it was created with, so a bound operation from another module does not change how the collection matches. Views, bound methods, and cleanup dispatch must carry the lexical module as part of their identity: two views of the same concrete receiver can select different module-local implementations at one call site, so a cache keyed by receiver type alone is wrong. Cached targets must never capture receiver values.

Verified: native collection creator evidence must survive clear, copying empty collections, and native operations returning derived collections. Re-stamping such a result with the caller's descriptor silently changes key identity. [Runtime stamping](../crates/ms-rt/src/map.rs) and [cross-module regressions](../tests/e2e/testdata/projects/preferred_names/conformance_test.ms) enforce preservation.

Apply when: changing implementation lookup, views, `match` on contract values, key or equality generation, or any call-site cache.
Evidence: [core parity project](../tests/e2e/testdata/projects/core_parity/conformance_test.ms), [local extensions project](../tests/e2e/testdata/projects/local_extensions/conformance_test.ms), [collection creator equality](../tests/e2e/testdata/projects/preferred_names/conformance_test.ms), [contract rules](../documentation/core-language/types/contracts.md#coherence-and-visibility).
Verify: run those three projects through `ms test`; alternate same-type views from two local-implementation modules at one nongeneric interface call site must each keep their own result.

### Lowering must honor checker conversions and avoid probing with side effects

Verified: checking can attach an implicit conversion (for example Optional wrapping of a plain argument) while the expression keeps its payload type. A lowering fast path that reads the raw expression instead of the converted argument stores the wrong representation, as a direct list call once did (`List[Optional[Int]]` held a bare Int and crashed). Error and Result widening composes with the Optional wrapper and stays in general expression lowering.

Verified: choose a lowering path before lowering its operands. Lowering mutates generator state (source markers, temporaries) even when its result is discarded, so an eligibility probe that lowers operands and then abandons them breaks exact-once invariants. Eligibility checks must return without lowering on an ineligible path. Keep the invariant assertion and an independent baseline rather than dropping unprinted markers.

Apply when: adding a lowering fast path, a direct call, or an optimization that tries one form then falls back.
Evidence: [lowering contract](../documentation/contributing/compiler/lowering/evaluation-order.md), [Optional argument fixture](../tests/e2e/testdata/accept/optional-arguments.ms), [collection conversion fixture](../tests/e2e/testdata/accept/direct-collection-conversions.ms).
Verify: a plain value passed to an Optional parameter inside a list call executes, and operands run once in written order.

### Evaluation order: receivers and operands are captured before later calls

Verified: a plain local read is not ordered against a later call unless the lowering orders it. A right-hand `match` or an index expression can reassign the receiver or the left operand local, so the receiver and each operand must be captured in written order before the operation that uses them, and prerequisites stay inside their short-circuit, match, and loop regions. Hoisting them changes source behavior.

Apply when: removing bound-call wrappers or lowering expressions to direct operations.
Evidence: [evaluation order](../documentation/contributing/compiler/lowering/evaluation-order.md), [receiver reassignment regression](../tests/e2e/testdata/accept/collection-call-order.ms), [operand order](../tests/e2e/testdata/accept/operand-order.ms).
Verify: a list receiver initially holding 7 still yields 7 when its index expression reassigns the local to a list holding 9.

### Checked Int arithmetic is language behavior

Decision: `Int` arithmetic faults on overflow ([design contract](../crates/DESIGN.md)). An optimizer may remove a check only with a proof that covers the whole result range (a literal divisor, an identity operand, a guarded counter step); unknown `+`, `-`, and `*` stay checked. Evaluate both operands even when the result is constant so effectful calls are preserved. A proof must be invalidated by every write to a cell it relies on, including peers modified in a loop body and closures, and must account for every loop prefix, not just the net delta.

Apply when: adding overflow-check elimination, bounds narrowing, or constant folding.
Evidence: [overflow faults](../tests/e2e/testdata/accept/numeric-faults.ms), [bounded arithmetic](../tests/e2e/testdata/accept/bounded-int-arithmetic.ms), [counter step](../tests/e2e/testdata/accept/counter-steps-keep-overflow-faults.ms), [int identities](../tests/e2e/testdata/accept/int-identities.ms).
Verify: reset and conditional-reset loops still fault with the overflow message; run `make conform`.

Verified: checked signed remainder differs from checked division at `MIN, -1`: remainder is zero while division faults. Constant folding must follow that distinction, and a variable numerator with divisor `-1` can fold to zero without removing evaluation of the numerator.
Evidence: [interpreter](../crates/ms-mir/src/interp.rs), [native lowering](../crates/ms-clif/src/lower.rs), [simplifier boundary regressions](../crates/ms-mir/tests/opt_simplify.rs).
Verify: run `cargo test -p ms-mir --test opt_simplify`; preserve zero-divisor faults and the checked division overflow.

Verified: an identical checked scalar operation can reuse an earlier dominating result because reaching the second operation proves the first succeeded. Keep the first check and its source location, even if only the repeat's result is used. This belongs in dominator-scoped value numbering; declaring checked operations globally pure would also permit unsafe speculation.
Evidence: [simplifier and checked-CSE regressions](../crates/ms-mir/tests/opt_simplify.rs), [dominator-scoped value numbering](../crates/ms-mir/src/opt/simplify.rs).
Verify: repeated checks across I/O and dominated blocks collapse; sibling checks, different operations, overflow and division faults keep their behavior.

Verified: list element replacement preserves length across loop parameters only when every incoming list has the same length origin. Length equality does not establish element equality. Appending, shrinking, replacing a list, or reading it afresh from memory starts a new origin; propagating a saved length across those operations can incorrectly remove bounds checks.
Literal-list sizes also bound indices and fold length reads; a new list's capacity does not make its initial length nonzero. Negative indexing still requires its normalization unless non-negativity is proven.
Evidence: [range analysis](../crates/ms-mir/src/opt/range.rs), [saved-length regressions](../crates/ms-mir/tests/opt_range.rs).
Verify: nested replacement loops eliminate redundant bounds checks; shrinking and conditional replacement still fault at an invalid index.

### Native omissions are declared in the standard declaration

Verified: defaults for native functions, methods, and constructor fields are written in the standard `.ms` declaration and checked as ordinary expressions. Constructor omission follows source metadata, application implementations inherit standard interface default permissions and receive concrete values, and native compositions pass `some(n)` through source-defined streams. Inferring permission or default expressions from a field's name would create a second schema; passing raw integers through an Optional interface would break source implementations.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [native default checking](../crates/ms-check/src/native_defaults.rs), [native defaults fixture](../tests/e2e/testdata/stdlib/defaults.ms), [stdlib revamp fixture](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: exercise stored, bound, and generic calls that omit a defaulted argument and fresh records; omit a limit through an application-defined ReadStream and match `none`.

### Fault locations name the failing operation's statement, without columns

Decision: the user rejected per-call bookkeeping in generated code; a fault captures its frames where it is created, and the process runs `with` cleanups in reverse order before aborting ([design contract](../crates/DESIGN.md)). Frames are `file:line in function` with no column, and a call spanning several lines reports the line of its statement's first line. A function's return-type position identifies its declaration, not a failing expression, so the located statement carries the position. Lower operands before the operation that can fault so a successful nested call does not take over the enclosing site. Do not reintroduce columns or per-call recording without a new decision.

Verified: omitted defaults lowered directly into a caller still need the callee's logical frame. Existing MIR inline scopes carry that frame without per-call runtime bookkeeping; default thunks already provide it. A source function must retain its declaration file even if its surviving instructions all come from an imported default.
Evidence: [default frame regressions](../crates/ms-cli/tests/default_frames.rs), [default lowering](../crates/ms-lower/src/call.rs), and the frozen `tests-e2e-testfaultsourcelocations-20` corpus fixture.

Apply when: adding lowered operations, inlining, source fault traces, or call fast paths.
Evidence: [expected failures](../tests/conformance/expect-fail.txt), [call depth fixture](../tests/e2e/testdata/accept/call-depth.ms), [fault and frame docs](../documentation/contributing/compiler/lowering/cleanup-and-faults.md).
Verify: `make conform` fault-location cases; preserve frame order, line numbers, and names.

Verified: the runaway-recursion corpus count reflects a one-million raw-frame traversal budget, not a call-depth limit. Recursion is admitted by stack size. Windows must count native callers after the same `fault_vec` anchor before spending the remaining budget on generated frames; removing its old 256-frame cap without preserving that shared budget produces a different repeat count. Never manufacture a source-frame count by subtracting guessed native overhead.
Evidence: [frame walkers and budget regressions](../crates/ms-rt/src/fault.rs), [Windows native unwind anchor](../crates/ms-rt/src/sys_windows.rs), [stack-size contract](../documentation/core-language/errors/faults.md).
Verify: native Windows shallow fault traces and the exact runaway-recursion corpus fixture; host synthetic-chain tests and cross-compilation alone cannot prove native unwind-entry identity.

Verified: LLVM translation must preserve cold-edge hints and identify runtime fault calls as `cold noreturn` while keeping their distinct source sites. Ordinary calls also need `nomerge`: merging equivalent calls from separate source paths can make a native fault name the other path's test or statement. Use exact runtime identities rather than a symbol prefix for semantic attributes: user function names can share a prefix. LLVM fault-frame tests must check bundled LLVM availability, not an unrelated clang installation.
Evidence: [LLVM translation and six-target object tests](../crates/ms-clif/src/llvm_ir.rs), [actual backend frame comparison](../crates/ms-cli/tests/llvm.rs), [runtime fault definitions](../crates/ms-rt/src/fault.rs).
Verify: generate and verify ELF, Mach-O and COFF for x86-64 and ARM64; run LLVM/Cranelift fault-frame equality on supported native hosts. Cross-target object generation establishes code generation, not native execution or runtime ABI correctness on another operating system.

Verified: LLVM glue inlining barriers must not depend on traversal order. Caching provisional recursive depths across roots made identical inputs choose different `noinline` functions. Count a cycle's closing edge once and exclude direct self calls; at the fixed three-edge threshold, two distinct non-leaf witnesses per callee suffice to answer every root without recursive context. This derivation is specific to three edges, not a general depth algorithm.
Evidence: [glue selection and bounded-traversal regressions](../crates/ms-clif/src/llvm_ir.rs), [deep-literal and source-frame guards](../crates/ms-cli/tests/llvm.rs).
Verify: compare definition/edge permutations and repeated actual LLVM input captures; preserve acyclic selections, recursive owned copy/drop behavior, fault frames and the deep-literal compile guard. Deterministic attributes alone do not establish runtime performance.

### Omitted library entries must stay empty through module loading

Verified: executable manifests require an entry; libraries omit the key, and an explicitly empty or invalid entry remains an error. Resolving an empty entry as a source path would turn it into the project directory, so graph loading skips that resolution and discovers source and test roots instead. Application commands report the missing entry at the manifest's project table; source analysis and test lowering use the same graph without requiring `main`.

Apply when: changing manifest modes, project discovery, editor overlays, or entry validation.
Evidence: [manifest parsing](../crates/ms-driver/src/project/manifest.rs), [library regressions](../crates/ms-driver/tests/project_library.rs), [graph loading](../crates/ms-driver/src/load.rs), [library contracts](../documentation/developer-tooling/builds/project-configuration.md#library-projects-and-copied-dependencies).
Verify: an omitted entry checks unimported modules and executes their tests; an explicit bad entry still fails (`cargo nextest run -p ms-driver`).

### Compiler passes use the right algorithm and data structure for their input size

Decision: the user wants parsing, checking, and lowering to stay linear (or n log n) in source size, with no ad-hoc special cases. A pass that re-walks a shared graph per root, scans a list per lookup, or allocates per-byte tables is a defect even when small inputs hide it.

Verified (Go-era probes, still the cases to re-run): walking the type dependency graph from every declaration made N chained types O(N squared) (8k types took 18.9 s, 0.35 s once the visited set was shared across roots; #490). A per-byte offset table was allocated for every lexed file though only CRLF needs one (#491). Nested literal checking was cubic for lists and quartic for maps because each level re-checked the item that had just supplied the element type; reuse the supplier's checked information, check only the literal's own bounds, and build type keys in one buffer.

Apply when: adding or changing a lexer, parser, checker, or lowering pass, or a cache or table they share.
Evidence: [type recursion pass](../crates/ms-check/src/recursion.rs), issues #490 and #491.
Verify: generate inputs at N, 2N, 4N (chained declarations, long function bodies, many matches, deeply nested literals), time `ms check` and `ms build` separately, and profile any step that grows faster than 2x per doubling. Prefer a global memo or index over a per-query rescan, and keep cycle checks ahead of memo hits.

Verified: collecting all caller constants at every inline candidate repeatedly scans a growing function. Index the caller once and extend the index with the appended callee blocks; the continuation contains old instructions and must not be scanned again. Keep the constant-argument bonus, growth budget and inlining decisions unchanged.
Evidence: [inliner](../crates/ms-mir/src/opt/inline.rs), [constant-bonus regression](../crates/ms-mir/tests/opt_inline.rs).
Verify: compare optimized MIR and native binaries before/after on real programs, and measure the entire build as well as the inline pass at N/2N/4N. A compiler-only improvement does not imply faster generated programs.

Verified: repeatedly recomputing use counts and scanning a function to delete the last unused instruction makes dead-expression chains quadratic. Decrement operand use counts as dead users are removed, and visit newly dead definitions with a worklist. Preserve faulting instructions and owned results as roots.
Evidence: [dead-code elimination](../crates/ms-mir/src/opt/simplify.rs), [dead-graph and unused-check regressions](../crates/ms-mir/tests/opt_simplify.rs).
Verify: simplify unused arithmetic chains at N/2N/4N; shared operands disappear without deleting an unused overflow check.

Verified: indexed last-use analysis must count pending drops at block start during both
liveness and placement. A descendant phi's drop can already be scheduled before the
first original instruction; filtering placement from instruction zero then removes
the parent's old drop without inserting a replacement. Use the block-start position
for incoming values and retain the after-definition bound for instruction results.
Evidence: [pending-family drop regression](../crates/ms-mir/tests/opt_lastuse.rs).
Verify: the regression fails ownership verification before the correction; Release
HTTP response/error paths retain the parent argument until its descendant is dropped.

Verified (2026-10-25): before this change a source `ref` function copied its result at `return`, so `ref` was checker-only and a lending accessor cost a subtree copy. A standard-library function declared `ref` now returns its borrow: the lent instance is a separate `$lent` instance (`Func.ret_borrowed`), its call result is a borrow the caller does not release, `return some(part)` builds `opt.view`, and a pattern variable the checker proved a read-only borrow of a borrowed parent is bound without a copy. An owned value on any path of a lent instance is a lowering error, which is why a function with an owned return (an interface call, whose result is always a copy) must not be lent: the checker records the `ref` functions whose every return lends in `Ownership.lenders` and only those get a `$lent` instance (user functions included); the rest copy at `return`. The inliner must give a `ret_borrowed` join parameter the borrow mode, and an owned scrutinee must never be aliased because it is dropped right after its payload is copied.
Evidence: [lending accessors](../tests/e2e/testdata/stdlib/json-accessors.ms), [lent results](../tests/e2e/testdata/accept/ref-lend-results.ms), [ownership corpus](../crates/ms-check/tests/ownership/accept/ref_some_payload.ms), `json.navigate` in [the stdlib bench](../bench/perf/stdlib/src/jsonbench.ms) (351 to 56 ns per three nested reads).
Verify: `ms test tests/e2e/testdata/stdlib/json-accessors.ms --build-type Release` with the debug `ms` (MIR verified after every pass) passes.

Verified: generic function recursion validation must not expand every path through an acyclic call graph. Repeated calls into a shared suffix made checking exponential in the number of declarations. Iterative sink removal identifies paths that cannot reach a cycle; skipping only those paths preserves recursive diagnostics and their order. A specialization-only memo is not interchangeable: the same specialization can be visited under different active ancestors, and reusing that result can hide a type-argument-changing cycle. Paths that lead to cycles still use the original ancestor-sensitive traversal.
Evidence: [generic recursion validation](../crates/ms-check/src/recursion.rs), [finite DAG and ancestor-context regressions](../crates/ms-check/tests/generic_recursion.rs).
Verify: a forty-level repeated-call DAG checks without expanding its trillion paths; direct and mutual cycles, changed arguments, acyclic tails, and same-spelled declarations in different modules keep their diagnostics. Do not claim that pruning acyclic suffixes makes cycle-containing graphs globally linear.

### Map word specialization requires the value representation to fit one word

Verified: String values occupy two words. Selecting the scalar map lookup path for
String-valued maps read later slots at the wrong stride even when iteration worked.
Restrict word-value specialization to supported scalar Int/Float representations;
use descriptor-based access for String and aggregate values.

Apply when: specializing map lookup or changing native map slot layout.
Evidence: [map native selection](../crates/ms-lower/src/rtcall.rs),
[multiple String-valued map entries](../tests/e2e/testdata/stdlib/map-string-values.ms).
Verify: insertion, contains, lookup and replacement agree for both String and Int keys
with multiple long String values under both Debug and Release.

### Cleanup registration preserves an owner even though normal calls borrow its bits

Verified: removing a copy used by `CleanupPush`, or moving its registered source,
can make fault cleanup free borrowed or already-transferred ownership. This caused
Release-only HTTP deadline allocator corruption and skipped middleware. Preserve
registered values in every copy-elimination path, including merged String owners
and Optional/variant unboxing. `lastuse` also treats registration as an escape.
Compiler-owned call temporaries register after argument evaluation and discard
immediately after normal return, before mutable writeback.

Automatic cancellation cleanup must follow that protected ownership through owning
block parameters and value updates. Exact SSA identity is insufficient: multipart
deadline recovery crashed when a loop phi was dropped automatically and then by
its explicit scope. A `Take` from a mutable receiver slot leaves the original bits
in storage; dropping it automatically can also double-release the caller's box.
Propagate protection through ownership transfers, but not independent `Copy`
references. The current analysis conservatively excludes all taken values and
owned results derived from protected arguments, even fresh results of consuming
calls; this can retain memory on cancellation and is not complete slot cleanup.

Apply when: optimizing ownership around callbacks or extending cleanup lowering.
Evidence: [copy elimination](../crates/ms-mir/src/opt/copyelim.rs),
[optimizer regressions](../crates/ms-mir/tests/opt_copyelim.rs),
[cancellation ownership regressions](../crates/ms-mir/tests/unwind.rs),
[HTTP deadline fixture](../tests/e2e/testdata/stdlib/http-deadlines.ms).
Verify: both code generators must execute the fault path, not merely verify MIR;
run the separate-process HTTP ownership recovery test under Debug and Release.
