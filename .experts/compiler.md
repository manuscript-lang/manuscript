# Compiler and build lessons

The Go implementation (generated Go, Go runtime, Go toolchain bundling) has been deleted; only the Rust and Cranelift implementation remains. Lessons that were specific to emitting or building Go are gone. What remains is what still constrains checking, lowering, and module loading.

### The implementation is Rust and Cranelift under a value-semantics model

Decision: on 2026-10-19 the owner directed moving the compiler, runtime, standard library, and tools off Go to Rust with Cranelift, under a value-semantics memory model: values have one owner and are dropped deterministically, `var` marks mutation, plain values copy and others move at their last use, and identity is explicit (`Shared`, `Weak`, `Arena`). The checked contract is in [the design contract](../crates/DESIGN.md) and [ownership notes](../crates/ms-check/OWNERSHIP.md); the [proposal](../proposals/rust-cranelift-backend.md) holds the plan and reasons. Parts of those documents still describe the Go oracle; it no longer exists, and the frozen conformance corpus is the behavior contract.

Verified (experiments, not the shipped toolchain): the same checked semantics in C ran 1.1x to 3.5x faster than the retired Go output, and a Cranelift spike compiled the kernels correctly in about 50 ms ([C baselines](../bench/perf/kernels/README.md#c-baselines-for-a-no-gc-backend), [spike](../experiments/cranelift-spike/README.md)). A non-atomic cancellation load is hoisted out of loops by Cranelift, and Cranelift 0.136's inliner mis-maps symbol global values.

Verified: the spike's checker was unsound, so passing well-formed programs and valgrind-clean runs do not show a memory model is safe. Reassigning a `match` scrutinee inside an arm frees what the payload bindings borrow; copy-in/copy-out `var` parameters double-free under unwinding once a callee reallocates and then faults. Exclusivity must be lexical per borrowing construct and proven by a soundness corpus, not by happy-path programs.

Apply when: changing ownership, borrowing, drop elaboration, or argument passing in the checker, MIR, or runtime.
Evidence: [ownership corpus](../crates/ms-check/tests/ownership.rs), [ownership notes](../crates/ms-check/OWNERSHIP.md), [proposal](../proposals/rust-cranelift-backend.md).
Verify: `cargo nextest run -p ms-check`, including the accept and reject ownership fixtures; add the rejected aliasing case before relaxing a rule.

### Generic instances resolve contract evidence in the instantiating module

Verified (carried from the retired implementation; the semantics are language rules): a module-local `impl` is visible only in its module, but a generic function from another module is instantiated with the caller's evidence for its bounded type variables, while operations on concrete types inside the body keep the declaring module's choice. A `Map` or `Set` keeps the equality and hashing it was created with, so a bound operation from another module does not change how the collection matches. Views, bound methods, and cleanup dispatch must carry the lexical module as part of their identity: two views of the same concrete receiver can select different module-local implementations at one call site, so a cache keyed by receiver type alone is wrong. Cached targets must never capture receiver values.

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
Verify: reset and conditional-reset loops still fault with the overflow message; run `make conform-rust`.

### Native omissions are declared in the standard declaration

Verified: defaults for native functions, methods, and constructor fields are written in the standard `.ms` declaration and checked as ordinary expressions. Constructor omission follows source metadata, application implementations inherit standard interface default permissions and receive concrete values, and native compositions pass `some(n)` through source-defined streams. Inferring permission or default expressions from a field's name would create a second schema; passing raw integers through an Optional interface would break source implementations.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [native default checking](../crates/ms-check/src/native_defaults.rs), [native defaults fixture](../tests/e2e/testdata/stdlib/defaults.ms), [stdlib revamp fixture](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: exercise stored, bound, and generic calls that omit a defaulted argument and fresh records; omit a limit through an application-defined ReadStream and match `none`.

### Fault locations name the failing operation's statement, without columns

Decision: the user rejected per-call bookkeeping in generated code; a fault captures its frames where it is created, and the process runs `with` cleanups in reverse order before aborting ([design contract](../crates/DESIGN.md)). Frames are `file:line in function` with no column, and a call spanning several lines reports the line of its statement's first line. A function's return-type position identifies its declaration, not a failing expression, so the located statement carries the position. Lower operands before the operation that can fault so a successful nested call does not take over the enclosing site. Do not reintroduce columns or per-call recording without a new decision.

Open: two conformance fixtures still differ (a multiline statement reports its last line; a callee inlined into `main` loses its frame). They are listed in `tests/conformance/rust-expect-fail.txt`.

Apply when: adding lowered operations, inlining, source fault traces, or call fast paths.
Evidence: [expected failures](../tests/conformance/rust-expect-fail.txt), [call depth fixture](../tests/e2e/testdata/accept/call-depth.ms), [fault and frame docs](../documentation/contributing/compiler/lowering/cleanup-and-faults.md).
Verify: `make conform-rust` fault-location cases; preserve frame order, line numbers, and names.

### Omitted library entries must stay empty through module loading

Verified: executable manifests require an entry; libraries omit the key, and an explicitly empty or invalid entry remains an error. Resolving an empty entry as a source path would turn it into the project directory, so graph loading skips that resolution and discovers source and test roots instead. Application commands report the missing entry at the manifest's project table; source analysis and test lowering use the same graph without requiring `main`.

Apply when: changing manifest modes, project discovery, editor overlays, or entry validation.
Evidence: [manifest parsing](../crates/ms-project/src/manifest.rs), [library regressions](../crates/ms-project/tests/library.rs), [graph loading](../crates/ms-driver/src/load.rs), [library contracts](../documentation/developer-tooling/builds/project-configuration.md#library-projects-and-copied-dependencies).
Verify: an omitted entry checks unimported modules and executes their tests; an explicit bad entry still fails (`cargo nextest run -p ms-project`).

### Compiler passes use the right algorithm and data structure for their input size

Decision: the user wants parsing, checking, and lowering to stay linear (or n log n) in source size, with no ad-hoc special cases. A pass that re-walks a shared graph per root, scans a list per lookup, or allocates per-byte tables is a defect even when small inputs hide it.

Verified (Go-era probes, still the cases to re-run): walking the type dependency graph from every declaration made N chained types O(N squared) (8k types took 18.9 s, 0.35 s once the visited set was shared across roots; #490). A per-byte offset table was allocated for every lexed file though only CRLF needs one (#491). Nested literal checking was cubic for lists and quartic for maps because each level re-checked the item that had just supplied the element type; reuse the supplier's checked information, check only the literal's own bounds, and build type keys in one buffer.

Apply when: adding or changing a lexer, parser, checker, or lowering pass, or a cache or table they share.
Evidence: [type recursion pass](../crates/ms-check/src/recursion.rs), issues #490 and #491.
Verify: generate inputs at N, 2N, 4N (chained declarations, long function bodies, many matches, deeply nested literals), time `ms check` and `ms build` separately, and profile any step that grows faster than 2x per doubling. Prefer a global memo or index over a per-query rescan, and keep cycle checks ahead of memo hits.
