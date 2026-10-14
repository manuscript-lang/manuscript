# Compiler and build lessons

### Generated Go serves performance; lowering code serves maintainability

Decision: the user wants highly optimized generated Go and explicitly permits
mechanical, non-idiomatic output. Erase high-level abstractions using checked
facts where semantics allow; readability of emitted Go is not a constraint.
Maintainable compiler code, precise source/debugger mapping, and supported
platform behavior remain requirements. Unsafe or runtime-internal techniques
need documented invariants and tests.

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

Decision: [the parent approved](https://github.com/manuscript-lang/manuscript/pull/315#issuecomment-6157745861)
borrowing argument arrays only for generated bodies that copy parameter Values
and cannot retain/expose the incoming slice. Capturing individual Values is safe;
arbitrary Go callbacks and unproven wrappers remain unmarked. Each `for_each`
invocation owns its buffer, including reentry. Native adapters call a raw body
with scalar/Value copies; ordinary source bodies bind slots before executing
source expressions. Generated tails keep the conservative constructor until
audited. Exercise [captured callback/reentry conformance](../tests/e2e/testdata/accept/typed-list-lowering.ms)
and [native marker/fault/cancellation checks](../pkg/build/typed_list_calls_test.go)
alongside runtime retention/allocation controls before expanding this seam.

Apply when: optimizing Go lowering, representations, calls, or collection access.
Evidence: [user direction](codex://threads/01a12c8b-2b5a-71ad-8446-e786ea4580df),
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

Verified: Go constant negation of `float64(0)` produces positive zero. Native
Float unary lowering must perform variable arithmetic (`FloatNegate`) so source
`-0.0`, IEEE sign bits and `toString()` retain negative zero. A direct source call
also needs an explicit IR expected-use edge when its argument is `Never`: faulting
arguments retain their source type while producing compilable typed Go. This
applies to List indexes, match arms and Boolean conditions/and/or/not as well.
Evidence: [native scalar lowering](../pkg/lower/lower_scalars.go),
[numeric source conformance](../tests/e2e/testdata/accept/numeric-lowering.ms),
[conversion conformance](../tests/e2e/testdata/accept/to-string.ms), and
[actual typed boundary tests](../pkg/build/typed_list_calls_test.go),
[IR Never native boundaries](../pkg/build/ir_never_native_test.go), and the
[shared IR contract](../documentation/contributing/compiler/lowering/typed-ir-contract.md).

Verified: selected methods are copied when the checker substitutes a receiver.
Pointer equality with the declaration does not identify that selection. Native
method lowering indexes the canonical checked method ID and retains dynamic
contract/default preparation when no concrete entry is available.
Evidence: [method selection](../pkg/checker/contracts.go),
[native method entries](../pkg/lower/lower_native_methods.go), and
[direct-method acceptance](../tests/e2e/testdata/accept/direct-methods.ms).
Verified: adopting expression IR can bypass a constructor optimization left in
the old syntax switch. List literals now reach `irValue(ir.List)` before that
switch; carry the published storage constructor into this exercised path and
remove the duplicate syntax implementation. Large-literal policy remains owned
by its optimization lane on the same IR path. Inspect emitted calls and execute
them: a type-correct boxed List can pass source semantics while losing primitive
storage and its allocation/retention properties.
Evidence: [authoritative IR lowering](../pkg/lower/lower_ir.go),
[elaboration](../pkg/ir/elaborate.go), and
[Release/Debug native backing regression](../pkg/build/ir_list_storage_native_test.go).
Verify: all four primitive literal kinds retain typed fresh backing, nested
lists retain boxed shallow identity, and effectful operands run left to right.
Retain the independently owned large-literal/debugger oracles and test the path
that actual expression dispatch exercises, rather than an unreachable branch.

### Native build levels need artifact evidence

Verified: Go omits recorded linker flags from build information when `-trimpath` is enabled. Check symbol/DWARF sections and executable size to verify stripping, rather than treating a missing recorded `-ldflags` value as a build failure. Both Debug and optimized RelWithDebInfo retain local source paths, so both need source-root-sensitive cache identities.

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
Evidence: [native assembly](../pkg/build/build.go), [shared workspace](../pkg/build/workspace.go), [command replay](../pkg/build/replay.go), [runtime variants](../pkg/build/variant.go), [lean stubs](../pkg/runtime/lean.go), [cache boundaries](../documentation/developer-tooling/builds/incremental-compilation.md), [standalone artifact invalidation](../tests/e2e/run_cache_test.go), and [native debugger checks](../extensions/vscode/tests/debug-adapter.test.js).
Verify: run native conformance and the native DAP test; compare both unchanged runs and edited-source builds with warm Go caches for Release and Debug. Unchanged runs exercise executable caching and do not establish runtime package reuse after edits. Check that replay profiles exist under the workspace and that a missing archive or tool falls back to `go build`.

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

### Fault sites must be recorded after operands finish

Verified: a function's return-type position identifies its declaration, not a failing expression. Generated functions retain a local source position and append one named frame while unwinding a fault. Update that position after evaluating an operation's operands: a successful nested call must not hide the enclosing operation's site, while an operand that faults must keep its own site. Statement fallbacks cover implicit operations; list destructuring records the pattern after evaluating its initializer.

Apply when: adding or specializing lowered runtime operations, source fault traces, or native call fast paths.
Evidence: [located lowering](../pkg/lower/lower_expressions.go), [source frames](../pkg/runtime/values.go), and [native location regressions](../tests/e2e/fault_locations_test.go).
Verify: run `TestFaultSourceLocations`, including multiline operands, argument faults, default arguments, bound methods, and destructuring; preserve exact frame order, columns, and names. Keep statement line directives on the operation rather than an inserted bookkeeping line.

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

### Nested collection checking reuses complete evidence

Verified: nested collection literals first inferred independent children, then
rebuilt the same trees under their inferred types. Combined with repeated
context classification and type comparisons, this made List checking cubic.
Nested Map bound walks additionally serialized every suffix type repeatedly.
Reuse complete same-type child evidence, scope contextual classification by
lexical identity, and visit bound graphs by checked type pointers. A literal
child owns its bound diagnostics; traversing it again at each parent duplicates
failures. Different callback labels, generic contexts and conversions still need
their ordinary checks. The parser's source nesting guard remains independent.
Evidence: [nested identity/context/allocation and bound-diagnostic regressions](../pkg/checker/collection_inference_test.go)
and [direct-AST checker runner](../scripts/bench-nested-literals/main.go).
Verify: doubling depth grows allocations approximately linearly; both 4K List
and Map ASTs terminate, nested empty lists report one missing leaf context, and
each invalid Map key reports at its own use site.
