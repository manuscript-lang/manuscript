# Compiler and build lessons

### Lowering is typed Go; do not reintroduce a universal value

Decision: the user directed one large refactor that removed `Value`, `any`, and boxing from generated Go and preferred Go idioms: every type lowers to exactly one Go type, records are `*Name`, alternatives are a sealed interface of case structs, functions are `func(*rt.Execution, A...) R`, and `rt.Option`/`rt.Result` are values. Earlier entries below that mention boxed locals, `Function.Body`, `CallMethod`, or lean runtimes describe the retired lowering.

Apply when: adding a type, a runtime representation, or a lowering fast path. Start from [Go representation](../documentation/contributing/go-lowering-representation.md); a fast path that needs a second representation of the same type is a design change, not a lowering detail.
Verify: `go test ./pkg/lower`, `make e2e stdlib-test`, and the accepted fixtures; read the emitted Go for a changed shape with `ms emit`.

### Generic instances resolve contract evidence in the instantiating module

Verified: a module-local `impl` is visible only in its module, but a generic function from another module is instantiated with that module's evidence for its bounded type variables, while operations on concrete types inside the body keep the declaring module's choice. The lowerer keys instances, views, and equality helpers by the scope chain (`g.scope`) when any module declares a local implementation, and matches contract values on `rt.ReceiverOf` so views from different scopes still match. A `Map` or `Set` keeps the `rt.Keys` it was created with, so a bound operation from another module does not change how the collection matches (the previous per-operation behavior was dropped on purpose).
Apply when: changing implementation lookup, views, `match` on contract values, key or equality generation.
Evidence: [scope resolution](../pkg/lower/func.go), [core parity project](../tests/e2e/testdata/projects/core_parity/main.ms), [local extensions](../tests/e2e/testdata/projects/local_extensions/main.ms), [collection creator equality](../tests/e2e/testdata/projects/preferred_names/main.ms).
Verify: run those three e2e projects; a view or helper cached by type alone breaks them.

### Defaults are evaluated by the callee

Decision: a defaulted parameter of a source function, method, lambda, or function type is `rt.Arg[T]`; the callee's prologue evaluates the default in its own scope so it can read earlier parameters and `try` returns from the callee. Natives, record constructors, and standard contracts keep plain parameters and call-site defaults. Generic record field defaults are lowered at the construction site with the record's type arguments substituted. A default's fault frame needs a `//line` of the default expression.
Evidence: [parameter prologue](../pkg/lower/func.go), [call-site defaults](../pkg/lower/call.go), and [field defaults across modules](../tests/e2e/e2e_test.go).
Verify: `TestFieldDefaultsAcrossModules`, `TestFaultSourceLocations/default_argument`, and a function used as a value whose defaulted-ness differs from its type.

### Int is Go `int`; 64-bit host values convert explicitly

Requested by Chinmay: `Int` lowers to Go `int` so it follows the platform width. Runtime natives take `int`; values that are inherently 64-bit (`Duration` nanoseconds, `Instant` ticks, `Timestamp` seconds, file sizes, hostos counters) stay `int64` and cross into Int with `FitInt` (faults when it does not fit) or `clampInt` (saturating counters). A blanket `int64`->`int` rewrite hides two traps: `any`/generic type switches (`JsonParseKey`, `JsonDecNative`) must match the new Go type, and `Duration(n)` must not pass through `int`. The checker still bounds literals at 64 bits, so a literal wider than the target `int` fails the Go build. Only 64-bit targets are exercised; `internal/hostos` does not build for 32-bit.

### The standard runtime declarations are generated

Decision: `pkg/runtime/std_*_gen.go` are written by `make stdgen` from the `@std` sources; `TestGeneratedRuntimeIsFresh` fails when they drift. Signatures belong to the declaration, so fix the `.ms` or the lowerer, regenerate, and implement what the `rtcheck` build reports. Do not edit generated files.

### Dispatch caches retain lexical view evidence

Verified: interface views of the same concrete receiver can select different
module-local implementations at one call site. Receiver type and registration
generation alone do not identify the target. Cache the lexical module as well;
argument scopes retain the ordinary specialization path rather than reusing a
previous no-argument entry. Cached targets must never capture receiver values.

Apply when: changing method dispatch, interface views or call-site caches.
Evidence: method dispatch and scope/cache regressions.
Verify: alternate same-type views from two local implementation modules at one
nongeneric interface call site, including concurrent calls, under the race detector.

### Generated Go serves performance; lowering code serves maintainability

Decision: the user wants highly optimized generated Go, on par with
hand-written Go, and explicitly permits mechanical, non-idiomatic output. Erase
high-level abstractions using checked facts where semantics allow; readability of
emitted Go is not a constraint. Maintainable compiler code, precise
source/debugger mapping, and supported platform behavior remain requirements.
Unsafe or runtime-internal techniques need documented invariants and tests.

Verified: keep `try` as one evaluation and a Go `if`/return. An exactly matching
failed Result can be returned directly; changing the success type or widening
the error still requires a result of the enclosing type. Test the discriminator,
since an error with empty text is still failure. Direct typed Result
literals avoid constructor-call inlining costs: on Go 1.25.1 they bring the
benchmark's `chain` from cost 91 to the ordinary budget of 80. An experiment
using `-l=4` for the runtime made more small checked methods inline, but was
rejected after the broader stdlib suite exposed regressions. Lower inlining
costs and wins in tiny call benchmarks alone do not establish an improvement.
Evidence: [try lowering](../pkg/lower/contracts.go),
[payload execution checks](../tests/e2e/testdata/accept/try-result-payloads.ms), and
[measurements and proposals](../bench/perf/programs/optimization-notes.md).

Decision: the language is designed to lower cheaply, so use Go's own
mechanisms. `try` returns the error as a Go value instead of panicking; source
methods become plain Go methods called directly; `Optional` and `Result` stay
typed rather than boxed; faults need not be checked per function, only caught at
the process or task boundary, so there is no per-call `defer`/`recover`
bookkeeping. Merged so far: nested `try` as early returns (#450), direct methods
of concrete records (#454), fault frames derived from the Go stack with
`file:line`-only caller frames and depth/cancellation sampled every 256th entry
in recursive cycles (#460), and typed `Result`/`Optional` for matched-only `let`s
(#462). Record fields, parameters, `var`s, captures, `List.at` payloads, and
closures remain boxed and are the next gaps. The skeptical review narrowed #462
because the record-field case was risky; a pointer-as-Optional was measured and
rejected for scalars, since `*T` allocates on every `some(Int)`.

Verified: concrete scalar locals can eliminate repeated boxing in arithmetic
loops, but unboxing a source-call result and reboxing it for the next call can
increase allocations. Classify uses and ABI boundaries before choosing a local
representation; Go's optimizer does not reliably remove those allocations.

Verified: primitive List storage also needs a use/ABI classification. The
[numeric List experiment](../bench/lists/README.md) separates boxed
storage from scalar-local boxing; its typed storage adds payload allocations
when fed through the unchanged Optional/comparator ABI. The production storage
review also found ordinary iteration/callback payload boxing and constant iterator
capture allocations; typed controls cannot replace these acceptance workloads.
See [the explicit allocation ledger](../bench/lists/typed-storage.md#review-correction-traversal-allocation-regressions). Preserve one authoritative
mutable handle across typed and generic aliases rather than keeping a boxed mirror.

Apply when: optimizing Go lowering, representations, calls, or collection access.
Evidence: [lowering direction and what it already does](../documentation/contributing/compiler/lowering/_index.md#typed-go),
[lowering objectives and staged scope](../documentation/contributing/compiler/lowering/_index.md),
and [generated/handwritten comparison](../bench/lowering/harness.go.txt).
Verify: run `go run ./bench/lowering` with the pinned SDK, inspect the
retained generated Go and escape analysis, and compare allocation counts as well
as runtime. Preserve fault, cancellation, aliasing, callback, and debugger tests
when promoting a benchmark candidate into production lowering.

Verified: immutable boxed literal tables still create fixed GC roots even when
their source functions never run. Per-construction B/op and Go HeapAlloc omit
that static data. The bounded Debug prototype measured zero/one/repeated calls,
multiple literals, child RSS and ELF segments; a lower GC target exposed a
repeatable construction slowdown despite faster native compilation. Treat those
as separate review costs. Evidence: [literal memory/runtime controls](../bench/debug-literals/README.md#current-matched-main-evidence-after-api-review).

Verified (#147): the Go compiler's cost for a large `[]rt.Value{int64(n), ...}`
literal is per item, not only per function: moving it into a helper function
did not help (100K Ints: ~26 s vs ~34 s raw `go build`), while pointer-free
typed package data (`[]int64{...}`) compiled in ~1.3 s over the empty-program
floor. Optimized builds therefore keep constant scalar items as pointer-free typed
package data; `rt.ListTable[T].List` copies it into a fresh typed List per
evaluation (typed primitive storage, #438), so nothing is boxed per item. Other
large literals keep chunked `[]rt.Value` items. Computed items are assigned in immediately called closures of at most 64; mark
each assignment with its item's source line, or the closures' physical lines
shift `//line` attribution for profiles and debuggers. Raise `expressionDepth`
around them exactly as match-expression closures do.
Evidence: large-list lowering,
shape tests, and
[native semantics/fault frames](../pkg/build/lower_large_lists_test.go).
Verify: `ms build` of 100K Int constants and of 16K calls; the native tests
mutate one of two evaluations and stop a literal via `try` and `return`.

Verified (#147): nested literal checking was cubic (lists) to quartic (maps)
because each level re-checked the item that had just supplied the element type,
`wellFormed` re-walked already-checked argument types, and `typeKey` built
nested keys by string concatenation. Reuse the supplier's checked info, check
only the literal's own bounds, and write keys into one builder. A nested empty
literal under an unknown expected type reports nothing more.
Evidence: [allocation-scaling and single-diagnostic tests](../pkg/checker/nested_literal_test.go).
Verify: depth-997 `[[...1...]]` checks in ~0.05 s (was ~5.3 s).

Verified: direct native calls must use `argumentValue`, not raw `expression`,
for supplied arguments. Checking can attach implicit Optional wrapping while
the expression retains its payload type; bypassing that evidence stored an Int
inside `List[Optional[Int]]` and caused an exit-70 conversion crash. Multi-argument
fast paths also retain ordered capture guards. Error/Result widening remains in
expression lowering and composes with the Optional wrapper.
Evidence: direct collection lowering,
generated-form checks,
and [native conversion/order conformance](../tests/e2e/testdata/accept/direct-collection-conversions.ms).

Verified: choose a lowering path before generating its operands. Explicit views
previously built and abandoned ordinary-call arguments, then lowered the receiver
again for `ViewOf`. A nested callable or match registered source markers in the
discarded tree, so checked programs failed the printer's exact-once invariant.
Lowering mutates generator state even when its resulting expression is discarded;
eligibility probes must return without lowering operands on an ineligible path.
Preserve the printer assertion and independent baseline rather than dropping
unprinted markers or rewriting source to introduce an intermediate binding.
Evidence: view lowering,
AST marker regressions,
[native evaluation/capture tests](../tests/e2e/testdata/accept/interface-view-callables.ms),
and [native DAP regression](../extensions/vscode/tests/interface-view-debug.test.js).

### Native build levels need artifact evidence

Verified: Go omits recorded linker flags from build information when `-trimpath` is enabled. Check symbol/DWARF sections and executable size to verify stripping, rather than treating a missing recorded `-ldflags` value as a build failure. Both Debug and optimized RelWithDebInfo retain local source paths, so both need source-root-sensitive build identity (`SourceRoot` in the build metadata).

Apply when: changing native optimization, symbol settings, or build caches.
Evidence: [build level contract](../documentation/developer-tooling/builds/build-levels.md), [native flags](../pkg/compiler/build_type.go), [cache identity](../pkg/build/cache.go), and [native artifact checks](../pkg/build/build_type_test.go).
Verify: build all four levels, execute and restore each artifact, check native optimization settings and debug sections, and compare stripped sizes with RelWithDebInfo.

Verified: replacing a large list constructor with an anonymous copy thunk
added physical Go lines under the preceding Manuscript `//line` directive.
Delve stopped at a later source breakpoint inside that thunk with missing
source locals. Giving the thunk a generated-file directive still introduced
an extra stepping frame. An in-statement `append([]rt.Value(nil), data[:]...)`
retains fresh storage without that frame; native DAP tests must compare against
the unchanged baseline, including existing bookkeeping-line coalescing.
Evidence: [large-list DAP regression](../extensions/vscode/tests/debug-large-literal.test.js),
bounded Debug lowering, and
[independent measurement/provenance](../bench/debug-literals/README.md).
Verify: break before and after construction, step, inspect source locals and
watches, and mutate one of two independent evaluations. Default/Release
generation and caller-edited `Result.Source` must remain unchanged.

### Native omissions are declared and preserved across interface dispatch

Verified: native defaults are written in the standard function, method, or constructor-field declaration and checked as ordinary expressions. Extended defaults use generated source preparation before the unchanged native ABI; existing Optional `= none` adapters retain their path. Constructor omission follows source metadata. Application implementations inherit standard interface default permissions and receive concrete values, while native compositions pass `some(n)` through source-defined streams. Inferring permission or expressions from a field's name would create a second schema; passing raw integers through an Optional interface would break source implementations.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [standard source checks](../pkg/checker/standard.go), [constructor/ABI regressions](../pkg/checker/stdlib_revamp_test.go), native emission, and [compiled stream boundary](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: inspect the generated defaults; exercise [native defaults](../tests/e2e/testdata/stdlib/defaults.ms), including stored/bound/generic calls and fresh records. Omit a limit through an application-defined ReadStream and match `none`; run read_line over that implementation and match its supplied `some(1)`. Keep native acquisition disposal at the final native delivery checkpoint; default preparation regressions cover cancellation and disposal. Migrate embedded source fixtures in native debugger tests too: an invalid constructor argument can leave a DAP launch waiting for initialization instead of surfacing its build diagnostic.

### Standalone runtime imports share one alias namespace

Verified: native builds keep the embedded runtime in its own package; merging it into the application forced Go to recompile host services after every source edit. Writing the 15 MB dependency bundle into a fresh directory took about as long as compiling and linking, and changing directories defeated package-cache reuse for Debug; a shared content-addressed workspace removed both. After that, the go command's package loading cost about 100 ms per edit, so rebuilds replay the traced compile/link of `package main` and fall back to `go build` on any mismatch. Linking was then the floor: about 230 ms Release, dominated by loading 108 MB of package archives, half of them `net/http`, `crypto/tls`, and gopsutil. Programs that import no network, system, or process module now link an `ms_lean` runtime without them (about 150 ms). Values of those modules' types only originate from their own functions, which makes module imports a sound selection rule. Keep heavy native dependencies in `!ms_lean` files, list their modules in the compiler's full-runtime set, and let the lean inventory test catch omissions. Per-process costs matter at this scale: loading standard declarations in `checker` package init cost 33 ms on every `ms` invocation, and garbage collection was about a third of that; load them on first use, overlap the pin with checking, and keep the language server on Go's default GC target. Keep single-file merging confined to `emit`. A separately compiled runtime also changes Delve type names, so debugger watches use Delve's `.(data)` rather than hard-coded `main.Record` assertions.
Decision: built executables are not cached (#362). Each source edit left a 5 MB executable that nothing removed, while a hit saved only the Go compile and link (about 0.3 s on a small program). `build` writes its output and `run`, `test`, `debug`, and `profile` build into a temporary directory; reuse comes from the shared workspace, Go's package cache, and replay profiles.
Evidence: [native assembly](../pkg/build/build.go), [shared workspace](../pkg/build/workspace.go), [command replay](../pkg/build/replay.go), [cache boundaries](../documentation/developer-tooling/builds/incremental-compilation.md), and [native debugger checks](../extensions/vscode/tests/debug-adapter.test.js).
Verify: run native conformance and the native DAP test; compare edited-source builds with warm Go caches for Release and Debug, since an unchanged rebuild no longer shows reuse of anything cached. Check that replay profiles exist under the workspace and that a missing archive or tool falls back to `go build`.

Verified: standalone generation merges runtime declarations and deduplicates imports by import path. Inconsistent aliases for the same Go package can pass ordinary runtime package compilation while breaking every emitted application. Platform helper packages also need inclusion in the standalone dependency bundle; embedding the main runtime sources alone does not carry imported repository packages.

Apply when: adding native runtime implementation files or platform adapters.
Evidence: [standalone merger](../pkg/build/build.go), [import-alias regression check](../pkg/build/library_test.go), [native dependency bundle](../embed.go), and [platform bridge](../internal/hostos/hostos.go).
Verify: `TestBundledRuntimeImportAliasesAgree`, source-to-native CLI tests, and the packaged binary check with an empty cache and no system Go.

Verified: native compilation must build the temporary module (`go build .`) rather than an absolute source filename. A filename build can give the main package the synthetic `command-line-arguments` identity and reject bundled internal imports when path canonicalization differs, as on macOS temporary paths. [Native build regression](../pkg/build/library_test.go) exercises a symlinked temporary root; [module build](../pkg/build/build.go) preserves the dependency namespace.

### Frontend independence retains runtime contract checks

Decision: native receiver signatures belong directly on the standard type or intrinsic interface. Do not duplicate them as private free functions. Native bindings identify implementations and any method-specific receiver requirements; the checker resolves requirements against checked standard types without importing the host runtime.

Verified: shared decimal literal rules and runtime receiver identities live in lightweight internal packages; the checker cannot import runtime/host dependencies under the repository policy. Native signature comparisons validate receiver types, parameters, results, generic variables, bounds, and binding coverage directly against receiver declarations, including deliberate mismatch regressions.

Apply when: adding standard operations or moving runtime code.
Evidence: [source receiver constraints](../pkg/checker/native_members.go), ABI tests, [dependency and bundle policy](../scripts/repo-check/policy.json), and [policy checks](../scripts/repo-check/main.go).
Verify: run `make verify` and native conformance. New bundled internal sources must enter the dependency bundle and implementation identity.

### Fault frames come from the Go stack and line directives

Decision: the user rejected per-call bookkeeping (`Enter`/`defer Leave` cost about 10 ns per call and fib(35) ran 9x Go). A fault captures its frames once, where it is created, from the Go stack: `RegisterSource` and `Named` map generated functions to source names, and `//line` directives give the file and line (#460). Frames are `file:line in function` with no column, and a call that spans several source lines reports its statement's line. Accepted costs: the depth limit may be exceeded by up to 256 frames, and a function without loops or recursive calls does not observe cancellation.

Verified: a function's return-type position identifies its declaration, not a failing expression, so the located statement carries the directive. Keep statement line directives on the operation, not on an inserted bookkeeping line, and keep operands lowered before the operation that can fault so a successful nested call does not take over the enclosing site.

Apply when: adding or specializing lowered runtime operations, source fault traces, native call fast paths, or anything that tempts per-call recovery or position tracking.
Evidence: located lowering, [frame capture](../pkg/runtime/frames.go), recursive-cycle admission, [lowering page](../documentation/contributing/compiler/lowering/_index.md#typed-go), and [native location regressions](../tests/e2e/fault_locations_test.go).
Verify: run `TestFaultSourceLocations`, including multiline operands, argument faults, default arguments, bound methods, and destructuring; preserve frame order, line numbers, and names. Do not reintroduce columns or `defer`-based recording without a new decision.

Verified: making default-bearing functions direct also makes their default
expressions part of the direct-call graph. Omitting defaults let a cycle through
a method exceed MaxCallDepth after integrating #507, even though body-only
recursion tests passed. Walk the declaration's parameters and body with the common
Callable visitor. Default-cycle lowering regressions distinguish this from merely
accepting the source.

Verified: Go orders calls in an expression, but that does not establish when an
earlier plain local read occurs relative to a later call. A right-hand match can
mutate the left local. Direct primitive equality therefore captures its operands
with ordered statements before comparing them. Keep prerequisites inside their
short-circuit, match and loop regions; hoisting them changes source behavior.
Evidence: primitive lowering,
[mutation/order conformance](../tests/e2e/testdata/accept/scalar-lowering.ms), and
native IEEE/fault checks.

### Omitted library entries must stay empty through graph loading

Verified: executable manifests previously required an explicit entry and had no default. Libraries now omit that key; an explicitly empty or invalid entry remains an error. Resolving an empty entry with `SourcePath` would turn it into the project directory, so graph loading skips that resolution and discovers source/test roots instead. Native application commands report the missing entry at the manifest's project table; source analysis and test lowering use the same graph without requiring `main`.

Apply when: changing manifest modes, project discovery, editor overlays, or entry validation.
Evidence: [manifest validation](../pkg/project/manifest.go), [graph loading](../pkg/frontend/modules.go), [library contracts](../documentation/developer-tooling/builds/project-configuration.md#library-projects-and-copied-dependencies), and [native regressions](../tests/e2e/library_project_test.go).
Verify: an omitted entry checks unimported modules and executes their tests; an explicit bad entry still fails. Check unsaved unimported library files, canonical symlink entry identities, confined alias targets, and test cache invalidation after an unimported source edit. Copied package content is not pinned.

### Compiler passes use the right algorithm and data structure for their input size

Decision: the user wants parsing, checking, and lowering to use the correct
algorithms and data structures so compile time stays linear (or n log n) in
source size, with no ad-hoc special cases. A pass that re-walks a shared graph
per root, scans a list per lookup, or allocates per-byte tables is a defect even
when small inputs hide it.

Verified: scaling probes found these before they reached users. Walking the type
dependency graph from every declaration made N chained types O(N²) (8k types:
18.9 s, 0.35 s once the visited set was shared across roots; #490). A per-byte
offset table was allocated for every lexed file though only CRLF needs one
(#491). Lowering matches on typed `Result`/`Optional` as `switch x.Tag()` on
strings made Go's SSA passes superlinear (4k matches in one function: 135 s to
build, 15.6 s with a bool-flag switch; #492). Remaining superlinear cost in very
large functions is inside the Go compiler.

Apply when: adding or changing a lexer, parser, checker, or lowering pass, or a
cache or table they share.
Evidence: #490, #491, #492; `pkg/checker/type_recursion.go`.
Verify: generate inputs at N, 2N, 4N (chained declarations, long function
bodies, many matches, deep nesting), time `ms check`, `ms emit`, and `ms build`
separately, and profile any step that grows faster than 2x per doubling. Prefer a
global memo or index over a per-query rescan, keep cycle checks ahead of memo
hits, and measure the emitted Go with `go build -gcflags=-cpuprofile`, since
`emit` can stay linear while the Go build does not.


### Indexing faults instead of narrowing
Verified: `list[index]` is `T` and lowers to `List_Get(ctx, list, index, None)`, which faults out of range; `get(index, default:)` supplies a fallback. The earlier flow-sensitive bounds proof (#552) only narrowed the type while lowering kept the faulting read, so it was removed along with its facts, loop handling, and the Optional allocation on every read.

Apply when: adding new lookup forms or reintroducing bounds-check elimination, which needs its own proof.
Evidence: `pkg/runtime/list.go` (`List_Get`), `pkg/lower/expr.go` (`indexValue`).
Verify: out-of-range `[]` faults with the index and length; `get` with a default never faults.

### Lowered Int hot paths keep faults but not avoidable calls
Verified: `Int` `/` and `%` by a positive literal cannot be zero, -1, or overflow, so they lower to Go's operators instead of `IntDivide`/`IntRemainder`; the loop cancellation poll is an inline `tick++; tick&63 == 0` on a plain local, because `Poll(ctx, &tick)` forced the counter into memory and halved a tight loop's speed (21.8 ms to 15.9 ms for 10M iterations). Integer identities (`+ 0`, `- 0`, `* 0`, `* 1`, including commuted `+`/`*`) also cannot overflow. Emit both operands in the Go operation to preserve effectful calls even when the result is constant. Unknown `+`, `-`, `*` stay checked: overflow faults are language behavior. Function-local interval proofs may remove only checks whose complete result range fits.

Apply when: changing Int arithmetic lowering or loop back-edge polling.
Evidence: `pkg/lower/expr.go` (`uncheckedIntArithmetic`), `pkg/lower/stmt.go` (`loopStatements`), `tests/e2e/int_literal_divisor_test.go`, `tests/e2e/int_identity_test.go`, `tests/e2e/numeric_lowering_test.go`.
Verify: compare `ms emit` output and `bench/perf/programs/run.sh` before and after; the fault tests must still pass.

### Guarded counter steps skip the overflow check
Verified: in `while i < n`, `i = i + 1` cannot overflow if it is the first statement in the body that assigns `i` (and `while i > n` with `i - 1` likewise), because locals change only by assignment in their own function and closures snapshot captures. `markCounterStep` in `pkg/lower/stmt.go` marks only that exact step; any earlier or nested assignment to `i` leaves the checked `IntAdd`. The measured gain is small (about 10% on a 10M-iteration counter loop), so widen it only with a benchmark.

Apply when: extending overflow-check elimination to other expressions (`i + k`, `<=` guards, `for` ranges).
Evidence: `pkg/lower/stmt.go`, `tests/e2e/counter_step_test.go`.
Verify: the reset and conditional-reset cases in the test must still fault with `Int overflow;`.

Verified: cancellation can reuse a literal-start unit-step counter while retaining
the exact 64th/128th poll phase. Unlike the overflow proof, this requires exactly
one unconditional assignment to the checked binding across the entire body and
no continue. Eligibility facts are body-local: preserve direct Int literal writes
and discard all facts at every other statement; do not scan backwards through
prefixes or carry facts across branches. Dynamic starts retained a live initial
value and regressed a prototype, so they keep the ordinary inline tick fallback.
Evidence: [poll selection and linear eligibility facts](../pkg/lower/stmt.go),
[eligibility pairs](../pkg/compiler/loop_poll_test.go),
[native phase oracle](../pkg/build/loop_poll_test.go), and
[measurements and assembly](../bench/perf/programs/results.md).
Verify negative/nonzero starts, both directions, nested entry, reset/continue
fallbacks, and source faults before widening the proof. Derive phase with raw Go
subtraction: modular overflow preserves the low six bits of the iteration count.
Use `(distance + 1) & 63 == 0` for the same phase with a cheaper zero test.


### Local interval proofs must cover prefixes and peer writes

Verified: scalar/list/one-field-record bounds use exact compiler arithmetic and
checked binding identities. Invalidate every modified cell before deriving any
loop delta; a peer's initial value is not an invariant. Budget positive and
negative contributions separately, including zero iterations and every prefix;
a safe net delta does not make an overflowing intermediate update safe. Explicit
Optional defaults are unknown unless their active payload is proved; none.Val is
not a default value. Unknown branches, statement expressions, closures and loops
kill facts rather than sharing speculative state.

Apply when: widening `pkg/lower/int_bounds.go`, `list_bounds.go` or `record_bounds.go`.
Evidence: [paired lowering tests](../pkg/compiler/int_bounds_test.go),
[list fallbacks](../pkg/compiler/list_bounds_test.go),
[record fallbacks](../pkg/compiler/record_bounds_test.go), and native fixtures
`bounded-int-arithmetic.ms`, `closed-int-list-bounds.ms`, `closed-record-int-bounds.ms`.
Verify native overflow, aliases/default evaluation, closure isolation, Debug,
standalone and source frames. Run `BenchmarkIntProofScaling` and
`BenchmarkClosedCellProofScaling` at N/2N/4N; profile excess doubling before
calling it linear. Epochs plus an undo journal avoid copying full fact maps at joins.

Verified: a closed-map storage proof inventories every use, including defaults,
match bodies and nested captures. Its compiler-only helpers reuse `*rt.Map[int,int]`
but interpret index values differently, so selecting only some consumers is
unsound. `add` returns the receiver: only discarded root calls can preserve the
no-alias proof. See [the storage contract](../documentation/contributing/go-lowering-representation.md#closed-local-int-maps).

Verified: `Program.ResolveMethods` scans the method registry. Cache global Int
map-evidence decisions once when no local implementations exist; otherwise a
linear AST inventory can still cost candidates times methods. Concrete record
specialization conservatively excludes generic callers that would re-resolve
methods per candidate. `BenchmarkClosedMapProofScaling` grows both dimensions.

Verified: successful Result bounds describe normal success returns, not call
totality. Even `return error(constructor(...))` can hide an early successful return
inside a match/block/default argument. Fixed-shape summaries reject such subtrees
and defaults. Expand wrappers from direct summaries only, not previously expanded
wrappers, to bound analysis independently of call-chain depth. During loop delta
collection, scope success bindings with journal rollback while all modified peers
stay unknown; never transfer accumulator assignments in that walk. See
`TestSuccessfulResultBoundsRejectDifferentReturns`, `TestSuccessfulResultBoundsRestoreElseScope`,
and `TestSuccessfulResultBoundsKeepPeerAndPrefixChecks`.
