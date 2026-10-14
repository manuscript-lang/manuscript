# Compiler and build lessons

### Generated Go serves performance; lowering code serves maintainability

Decision: the user wants highly optimized generated Go, on par with
hand-written Go, and explicitly permits mechanical, non-idiomatic output. Erase
high-level abstractions using checked facts where semantics allow; readability of
emitted Go is not a constraint. Maintainable compiler code, precise
source/debugger mapping, and supported platform behavior remain requirements.
Unsafe or runtime-internal techniques need documented invariants and tests.

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
[numeric List experiment](../scripts/bench-lists/README.md) separates boxed
storage from scalar-local boxing; its typed storage adds payload allocations
when fed through the unchanged Optional/comparator ABI. The production storage
review also found ordinary iteration/callback payload boxing and constant iterator
capture allocations; typed controls cannot replace these acceptance workloads.
See [the explicit allocation ledger](../scripts/bench-lists/typed-storage.md#review-correction-traversal-allocation-regressions). Preserve one authoritative
mutable handle across typed and generic aliases rather than keeping a boxed mirror.

Apply when: optimizing Go lowering, representations, calls, or collection access.
Evidence: [lowering direction and what it already does](../documentation/contributing/compiler/lowering/_index.md#structured-go-generation),
[lowering objectives and staged scope](../documentation/contributing/compiler/lowering/_index.md),
and [generated/handwritten comparison](../scripts/bench-lowering/harness.go.txt).
Verify: run `go run ./scripts/bench-lowering` with the pinned SDK, inspect the
retained generated Go and escape analysis, and compare allocation counts as well
as runtime. Preserve fault, cancellation, aliasing, callback, and debugger tests
when promoting a benchmark candidate into production lowering.

Verified: immutable boxed literal tables still create fixed GC roots even when
their source functions never run. Per-construction B/op and Go HeapAlloc omit
that static data. The bounded Debug prototype measured zero/one/repeated calls,
multiple literals, child RSS and ELF segments; a lower GC target exposed a
repeatable construction slowdown despite faster native compilation. Treat those
as separate review costs. Evidence: [literal memory/runtime controls](../scripts/bench-debug-literals/README.md#current-matched-main-evidence-after-api-review).

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
Evidence: [large-list lowering](../pkg/lower/lower_large_lists.go),
[shape tests](../pkg/lower/lower_large_lists_test.go), and
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
Evidence: [direct collection lowering](../pkg/lower/lower_collections.go),
[generated-form checks](../pkg/compiler/lower_collection_conversions_test.go),
and [native conversion/order conformance](../tests/e2e/testdata/accept/direct-collection-conversions.ms).

Verified: choose a lowering path before generating its operands. Explicit views
previously built and abandoned ordinary-call arguments, then lowered the receiver
again for `ViewOf`. A nested callable or match registered source markers in the
discarded tree, so checked programs failed the printer's exact-once invariant.
Lowering mutates generator state even when its resulting expression is discarded;
eligibility probes must return without lowering operands on an ineligible path.
Preserve the printer assertion and independent baseline rather than dropping
unprinted markers or rewriting source to introduce an intermediate binding.
Evidence: [view lowering](../pkg/lower/lower_expressions.go),
[AST marker regressions](../pkg/lower/lower_views_test.go),
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
[bounded Debug lowering](../pkg/lower/lower_debug_literals.go), and
[independent measurement/provenance](../scripts/bench-debug-literals/README.md).
Verify: break before and after construction, step, inspect source locals and
watches, and mutate one of two independent evaluations. Default/Release
generation and caller-edited `Result.Source` must remain unchanged.

### Native omissions are declared and preserved across interface dispatch

Verified: native defaults are written in the standard function, method, or constructor-field declaration and checked as ordinary expressions. Extended defaults use generated source preparation before the unchanged native ABI; existing Optional `= none` adapters retain their path. Constructor omission follows source metadata. Application implementations inherit standard interface default permissions and receive concrete values, while native compositions pass `some(n)` through source-defined streams. Inferring permission or expressions from a field's name would create a second schema; passing raw integers through an Optional interface would break source implementations.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [standard source checks](../pkg/checker/standard.go), [constructor/ABI regressions](../pkg/checker/stdlib_revamp_test.go), [native emission](../pkg/lower/lower_functions.go), and [compiled stream boundary](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: inspect the generated defaults; exercise [native defaults](../tests/e2e/testdata/stdlib/defaults.ms), including stored/bound/generic calls and fresh records. Omit a limit through an application-defined ReadStream and match `none`; run read_line over that implementation and match its supplied `some(1)`. Keep native acquisition disposal at the final native delivery checkpoint; [default preparation regressions](../pkg/runtime/defaults_test.go) cover cancellation and disposal. Migrate embedded source fixtures in native debugger tests too: an invalid constructor argument can leave a DAP launch waiting for initialization instead of surfacing its build diagnostic.

### Standalone runtime imports share one alias namespace

Verified: native builds keep the embedded runtime in its own package; merging it into the application forced Go to recompile host services after every source edit. Writing the 15 MB dependency bundle into a fresh directory took about as long as compiling and linking, and changing directories defeated package-cache reuse for Debug; a shared content-addressed workspace removed both. After that, the go command's package loading cost about 100 ms per edit, so rebuilds replay the traced compile/link of `package main` and fall back to `go build` on any mismatch. Linking was then the floor: about 230 ms Release, dominated by loading 108 MB of package archives, half of them `net/http`, `crypto/tls`, and gopsutil. Programs that import no network, system, or process module now link an `ms_lean` runtime without them (about 150 ms). Values of those modules' types only originate from their own functions, which makes module imports a sound selection rule. Keep heavy native dependencies in `!ms_lean` files, list their modules in the compiler's full-runtime set, and let the lean inventory test catch omissions. Per-process costs matter at this scale: loading standard declarations in `checker` package init cost 33 ms on every `ms` invocation, and garbage collection was about a third of that; load them on first use, overlap the pin with checking, and keep the language server on Go's default GC target. Keep single-file merging confined to `emit`. A separately compiled runtime also changes Delve type names, so debugger watches use Delve's `.(data)` rather than hard-coded `main.Record` assertions.
Decision: built executables are not cached (#362). Each source edit left a 5 MB executable that nothing removed, while a hit saved only the Go compile and link (about 0.3 s on a small program). `build` writes its output and `run`, `test`, `debug`, and `profile` build into a temporary directory; reuse comes from the shared workspace, Go's package cache, and replay profiles.
Evidence: [native assembly](../pkg/build/build.go), [shared workspace](../pkg/build/workspace.go), [command replay](../pkg/build/replay.go), [runtime variants](../pkg/build/variant.go), [lean stubs](../pkg/runtime/lean.go), [cache boundaries](../documentation/developer-tooling/builds/incremental-compilation.md), and [native debugger checks](../extensions/vscode/tests/debug-adapter.test.js).
Verify: run native conformance and the native DAP test; compare edited-source builds with warm Go caches for Release and Debug, since an unchanged rebuild no longer shows reuse of anything cached. Check that replay profiles exist under the workspace and that a missing archive or tool falls back to `go build`.

Verified: standalone generation merges runtime declarations and deduplicates imports by import path. Inconsistent aliases for the same Go package can pass ordinary runtime package compilation while breaking every emitted application. Platform helper packages also need inclusion in the standalone dependency bundle; embedding the main runtime sources alone does not carry imported repository packages.

Apply when: adding native runtime implementation files or platform adapters.
Evidence: [standalone merger](../pkg/build/build.go), [import-alias regression check](../pkg/build/library_test.go), [native dependency bundle](../native_bundle.go), and [platform bridge](../internal/hostos/hostos.go).
Verify: `TestBundledRuntimeImportAliasesAgree`, source-to-native CLI tests, and the packaged binary check with an empty cache and no system Go.

Verified: native compilation must build the temporary module (`go build .`) rather than an absolute source filename. A filename build can give the main package the synthetic `command-line-arguments` identity and reject bundled internal imports when path canonicalization differs, as on macOS temporary paths. [Native build regression](../pkg/build/library_test.go) exercises a symlinked temporary root; [module build](../pkg/build/build.go) preserves the dependency namespace.

### Frontend independence retains runtime contract checks

Decision: native receiver signatures belong directly on the standard type or intrinsic interface. Do not duplicate them as private free functions. Native bindings identify implementations and any method-specific receiver requirements; the checker resolves requirements against checked standard types without importing the host runtime.

Verified: shared decimal literal rules and runtime receiver identities live in lightweight internal packages; the checker cannot import runtime/host dependencies under the repository policy. Native signature comparisons validate receiver types, parameters, results, generic variables, bounds, and binding coverage directly against receiver declarations, including deliberate mismatch regressions.

Apply when: adding standard operations or moving runtime code.
Evidence: [source receiver constraints](../pkg/checker/native_members.go), [ABI tests](../pkg/checker/library_test.go), [dependency and bundle policy](../scripts/repo-check/policy.json), and [policy checks](../scripts/repo-check/main.go).
Verify: run `make verify` and native conformance. New bundled internal sources must enter the dependency bundle and implementation identity.

### Fault frames come from the Go stack and line directives

Decision: the user rejected per-call bookkeeping (`Enter`/`defer Leave` cost about 10 ns per call and fib(35) ran 9x Go). A fault captures its frames once, where it is created, from the Go stack: `RegisterSource` and `Named` map generated functions to source names, and `//line` directives give the file and line (#460). Frames are `file:line in function` with no column, and a call that spans several source lines reports its statement's line. Accepted costs: the depth limit may be exceeded by up to 256 frames, and a function without loops or recursive calls does not observe cancellation.

Verified: a function's return-type position identifies its declaration, not a failing expression, so the located statement carries the directive. Keep statement line directives on the operation, not on an inserted bookkeeping line, and keep operands lowered before the operation that can fault so a successful nested call does not take over the enclosing site.

Apply when: adding or specializing lowered runtime operations, source fault traces, native call fast paths, or anything that tempts per-call recovery or position tracking.
Evidence: [located lowering](../pkg/lower/lower_expressions.go), [frame capture](../pkg/runtime/frames.go), [recursive-cycle admission](../pkg/lower/lower_recursion.go), [lowering page](../documentation/contributing/compiler/lowering/_index.md#structured-go-generation), and [native location regressions](../tests/e2e/fault_locations_test.go).
Verify: run `TestFaultSourceLocations`, including multiline operands, argument faults, default arguments, bound methods, and destructuring; preserve frame order, line numbers, and names. Do not reintroduce columns or `defer`-based recording without a new decision.

Verified: making default-bearing functions direct also makes their default
expressions part of the direct-call graph. Omitting defaults let a cycle through
an accessor exceed MaxCallDepth after integrating #507, even though body-only
recursion tests passed. Walk the declaration's parameters and body with the common
Callable visitor. [Default-cycle lowering](../pkg/lower/lower_accessors_test.go)
and [bounded native depth/cancellation](../pkg/build/accessors_native_test.go)
regressions distinguish this from merely accepting the source.

Verified: Go orders calls in an expression, but that does not establish when an
earlier plain local read occurs relative to a later call. A right-hand match can
mutate the left local. Direct primitive equality therefore captures its operands
with ordered statements before comparing them. Keep prerequisites inside their
short-circuit, match and loop regions; hoisting them changes source behavior.
Evidence: [primitive lowering](../pkg/lower/lower_equality.go),
[mutation/order conformance](../tests/e2e/testdata/accept/scalar-lowering.ms), and
[native IEEE/fault checks](../pkg/build/lower_scalar_native_test.go).

### Omitted library entries must stay empty through graph loading

Verified: executable manifests previously required an explicit entry and had no default. Libraries now omit that key; an explicitly empty or invalid entry remains an error. Resolving an empty entry with `SourcePath` would turn it into the project directory, so graph loading skips that resolution and discovers source/test roots instead. Native application commands report the missing entry at the manifest's project table; source analysis and test lowering use the same graph without requiring `main`.

Apply when: changing manifest modes, project discovery, editor overlays, or entry validation.
Evidence: [manifest validation](../pkg/project/manifest.go), [graph loading](../pkg/frontend/modules.go), [library contracts](../documentation/developer-tooling/builds/project-configuration.md#library-projects-and-copied-dependencies), and [native regressions](../tests/e2e/library_project_test.go).
Verify: an omitted entry checks unimported modules and executes their tests; an explicit bad entry still fails. Check unsaved unimported library files, canonical symlink entry identities, confined alias targets, and test cache invalidation after an unimported source edit. `ms.lock` pins build inputs and never claims to pin copied package content.

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

