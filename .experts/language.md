# Language lessons

### An unsaved overlay cannot replace a dangling source symlink

Verified: editor overlays may create a file beneath an existing confined directory, but a dangling symlink remains a filesystem entry whose target identity must be respected. Treating every `EvalSymlinks` not-found result as an unsaved file allowed an overlay to hide an unresolved external target. Source path resolution now rejects that fallback for existing entries.

Apply when: changing project resolution, filesystem identity, or editor overlays.
Evidence: [source path resolution](../pkg/project/paths.go), [symlink/overlay regressions](../pkg/project/project_test.go), and [strict versus recovery compilation](../pkg/build/metadata_test.go).
Verify: new confined overlay files compile without being written to disk; overlays for outside paths, dangling external links, or symlinked external parents are rejected. Normalize accepted overlay keys to canonical file identity so symlinked workspace directories retain unsaved content; reject conflicting snapshots of one file. Recovery keeps valid declarations while diagnostics still prevent generated executable source.

### String conversion is available on every value

Decision: the user requested conversion with `toString()` on everything. This supersedes the previous restriction of interpolation to scalars. Conversion is available in unconstrained generic code and uses the same representations as interpolation; ordinary type compatibility at assignment, call, and return boundaries remains explicit.

Apply when: changing interpolation, member resolution, formatting, or editor member queries.
Evidence: [canonical conversion rules](../documentation/core-language/basics/text-and-bytes.md#converting-values-to-string); [native source conformance](../tests/e2e/testdata/accept/to-string.ms); [opaque and cyclic formatting checks](../pkg/runtime/format_test.go).
Verify: a record and an unconstrained `T` both support `.toString()` and direct interpolation; a closed resource converts without invoking an operation; passing that record directly to a String parameter is still rejected.

### Invalid bounds must not survive recovery

Verified: reporting an invalid bound without removing it lets implementation substitution turn a variable bound into a self-referential graph. Diagnostic hints and editor member discovery must terminate even on malformed bound graphs. Keep valid interface bounds such as `T: Compare[T]`; reject variable bounds such as `T: T` without attaching them as evidence.

Apply when: resolving generic bounds, copying implementation variables, or traversing recovered types for diagnostics and editor queries.
Evidence: [bounded crash regression](../pkg/checker/bound_recovery_test.go), [editor recovery](../pkg/tooling/lsp/bound_recovery_test.go), and [native interface-bound fixture](../tests/e2e/testdata/accept/recursive-interface-bound.ms).

### Local implementations must remain selected across module boundaries

Verified: accepting an implementation for an imported source type requires more than relaxing receiver ownership. The checker limits extensions to their declaring module; views, bound methods, cleanup, and generic specialization retain that selection at runtime. A global receiver/contract lookup would silently select another module's extension. Inherited receiver bounds also need their resolved nominal identities, rather than resolving their source spelling again in the extending module.

Apply when: changing implementation visibility, generic evidence, contract wrappers, cleanup dispatch, or editor member lookup.
Evidence: [coherence and visibility](../documentation/core-language/types/contracts.md#coherence-and-visibility); [boundary and inherited-bound checks](../pkg/compiler/local_extensions_test.go); [native cross-module dispatch fixture](../tests/e2e/testdata/projects/local_extensions/main.ms); [editor visibility and navigation](../pkg/tooling/lsp/completion_test.go).
Verify: two modules implement the same imported pair with different results; returned views and specialized functions retain their results, while raw values do not acquire either extension in a third module. Forwarding a generic argument must not change dispatch on statically concrete receivers in the callee.

### Read the current decision before restoring an older design

Decision: the language rebuild was directed to use the new design on `main`. Earlier designs and assistant proposals can conflict with subsequent user corrections. Establish the target contract from the latest direction and canonical pages before borrowing old implementation ideas.

Apply when: rebuilding a feature, reusing historical code, or reconciling branches.
Evidence: [design index](../documentation/_index.md).
Verify: the accepted/rejected source cases agree with the intended design, and any checkout mismatch is identified before being treated as a rule.

### Removing a construct includes its surrounding APIs

Decision: the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests. The user wanted ordinary `if`/`return` control flow. Removing the syntax alone did not satisfy the requested surface.

Apply when: removing or renaming language constructs or standard APIs.
Evidence: none recorded.
Verify: inventory related exported helpers and aliases before editing, regenerate references, then check every surface covered by the removal request. Follow an explicit zero-reference request when deciding whether rejection tests should retain the old spelling.

Verified: when rebasing standard-library work onto current main, migrate new conformance fixtures and documentation examples to ordinary `if not (...)` checks returning `panic`; do not restore the removed testing module or its native bindings from a stash. The source-level [built-in parity fixture](../tests/e2e/testdata/accept/builtin-parity.ms) exercises this form, and [standard bindings](../pkg/stdlib/bindings.json) remain free of the removed module.

### Error translation does not need a dedicated standard helper

Decision: remove the specialized Result error-mapping helper and keep domain translation in ordinary functions and matching. The newer error simplification permits specific errors to pass directly into the standard Error boundary, including through `try`; unrelated domain errors still require explicit translation. Do not restore a dedicated mapping helper.

Decision: the user requested "please remove nested match from everywhere, note it as anti pattern and ensure it never gets repeated", then reaffirmed "nested match is anti pattern, solve it another way". This includes implementation, examples, documentation and diagnostic remedies. Keep grammar and execution semantics available for compatibility and meaningful syntax/semantic regressions. Use compatible `try`, early-exit payload bindings, Optional methods, or small helpers; the user also rejected elaborate loading examples, so avoid contrived domain models and helper layers added only to make an example work.

Verified: [MSL107](../pkg/tooling/nested_match_lint.go) warns at each structurally inner match; the [repository guard](../scripts/repo-check/nested_match.go) inspects source, fences, and Go strings. Test allowances are scoped and require a reason. [CLI/editor regressions](../internal/cli/advisory_lint_test.go) preserve checking success and advisory status. The earlier local completion report did not establish publication; the reconciliation used current main and the actual code registry, where MSL104/105 are already allocated and MSL106 belongs to the payload-binding rule.

Apply when: adding Result adapters or rewriting examples that combine execution and domain errors.
Evidence: [flat flow and grammar compatibility](../documentation/core-language/control-flow/pattern-matching.md#keep-match-flow-flat); [error compatibility](../documentation/core-language/errors/propagation.md#error-compatibility); [task group example](../pkg/stdlib/tasks.ms).
Verify: examples compile with compatible `try` calls and introduce only the concepts they teach. Result's success-only `map` and same-error `and_then` retain the original error payload; they do not add an error-translation helper. The standard Result module exports only its type, and regenerated API references agree with its declarations. [Called composition tests](../tests/e2e/testdata/stdlib/core-parity.ms) distinguish success transformation from error translation.

### Equality and hashing are source interfaces

Decision: the stdlib revamp explicitly replaces compiler-only equality/hashing bounds with `Equal` and `Hashable` interfaces. Data keeps reference semantics (no move to value semantics was adopted), and explicit implementations select domain identity. Custom equality requires an explicit consistent hash before the type becomes a key; structural hashing cannot silently use different fields.

Apply when: changing equality operators, generic bounds, contract views, key lookup, or implementation visibility.
Evidence: [equality rules](../documentation/core-language/types/equality-and-hashing.md), [source interfaces](../pkg/stdlib/equality.ms), and [compiled domain-key fixture](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: two keys with equal IDs and different labels compare equal and occupy one map entry; an equality override without a hash is rejected as a map key. Keep local implementation selection when forwarding generic arguments.

Decision: all values may be passed freely; shared mutable state uses Synchronized, and closures have ordinary captures. This remains independent of equality, hashing, cleanup, and work lifetime.
Evidence: [sharing rules](../pkg/stdlib/sync.ms).

### Syntax improvements need examples across their boundaries

Decision: support grouped symbol imports and brace Map literals. The user's newer explicit request to “remove mandatory labels for invoking functions” supersedes the prior restriction to single-parameter unlabeled calls. Invocation labels are optional across functions, methods, function values and constructors. Preserve existing matching-name shorthand; changing every bare identifier to positional would silently change valid reordered calls. Keep callback function-type label identity separate from invocation syntax, including the contextual-lambda label adoption rule.

Apply when: changing calls, grammar, inference or editor assistance.
Evidence: [canonical call rules](../documentation/core-language/functions/declarations-and-calls.md#argument-names); [binding/source preservation tests](../pkg/checker/positional_arguments_test.go); [native calls](../tests/e2e/testdata/accept/positional-arguments.ms).
Verify: positional/labeled/mixed calls bind deterministically, old reordered shorthand retains its meaning, supplied values execute once in written order before defaults, and callback mismatched names remain rejected. Editor rename must make implicit argument labels explicit when renaming could change binding. Open (issue #452): a bare identifier can silently select another parameter; [MSL109](../pkg/tooling/bare_argument_lint.go) warns without changing binding, while making bare arguments positional remains an undecided language change needing a migration for reordered shorthand calls.

### Recover concrete contract receivers through checked matching

Decision: a common Error contract must allow generic diagnostics and specific handling without discarding the concrete error. The user requested constructing errors once and passing them directly into the root Error interface. An explicit implementation establishes the relationship; assignments, arguments, returns, Result error widening, and `try` can use it without a written view conversion. Ordinary domain fields contain typed details. Unrelated domains and other interfaces retain exact compatibility. Contract matches use concrete record/alternative type patterns with exactly one receiver binding and a final wildcard for other implementations.

Verified: direct or stored standard error `message` methods dispatch through the registered Error implementation, rather than intrinsic receiver dispatch. Receiver type parameters belong to the implementation, not method-level inference. The [compiled error fixture](../tests/e2e/testdata/accept/library-errors.ms) exercises direct and stored diagnostics alongside generic error views.

Apply when: changing Error boundaries, contract views, matching, or native standard implementations.
Evidence: [contract type patterns](../documentation/core-language/control-flow/pattern-matching.md#contract-type-patterns); [common error boundary](../documentation/core-language/errors/results.md#a-common-error-boundary); [compiled errors and generic patterns](../tests/e2e/testdata/accept/library-errors.ms); [invalid contract patterns](../pkg/build/library_test.go).
Verify: exact nominal identities and generic arguments determine a match; the receiver and payload survive conversion and propagation; missing implementations, incomplete generic patterns, and missing fallbacks are rejected.

### Default arguments must not leak across callable replacement

Decision: ordinary record fields may have default expressions. Verified: constructors evaluate supplied arguments before omitted defaults in field order, with earlier fields available to later defaults; explicit values skip defaults and each construction evaluates fresh storage. The user explicitly requires standard runtime functions to appear as syntactically correct empty functions, with their full declarations and ordinary colon headers; do not introduce a `native` keyword or hide invalid syntax in editor analysis. Evidence: [record construction rules](../documentation/core-language/types/records.md#construction), [field-default conformance](../tests/e2e/testdata/accept/field-defaults.ms), and [rejection checks](../pkg/compiler/field_defaults_test.go).

Verified: defaults are permissions on a known callable, not part of function-type identity. Retaining that permission on a mutable binding or inferred generic type could let a required-argument function replace a defaulted function, then be called with a missing argument. Explicit function types, mutable bindings, and generic inference erase defaults; inferred immutable copies retain them.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../documentation/core-language/functions/declarations-and-calls.md#default-arguments); [boundary rejection tests](../pkg/checker/defaults_test.go); [native default behavior](../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.

### Mutable data uses explicit shallow cloning

Decision: ordinary record fields and collections are mutable. The user rejected immutable replacement APIs and instance freezing in favor of `.clone()`. Preserve `let`/`var` binding rules independently of object mutation. Clone data storage shallowly; do not manufacture copies of sockets, files, locks, or other native service handles. A cloned record may retain the same handle reference.

Apply when: changing fields, collection updates, aliases, copies, equality, or concurrency guidance.
Evidence: [record contract](../documentation/core-language/types/records.md#mutation-and-cloning); [collection contract](../documentation/core-language/types/collections.md#mutation-and-copies); [native conformance](../tests/e2e/testdata/accept/mutation.ms); [resource clone rejection](../pkg/compiler/mutation_test.go); [CLI rejection and shared file lifetime](../tests/e2e/mutation_test.go).
Verify: the counter's Unit-returning method updates `self.val`; aliases observe mutation; a clone's outer storage stays separate while its nested references remain shared. Native resource clone calls are rejected. Protect concurrent mutation with existing Synchronized guards; do not restore removed sharing bounds.

### Source-backed data types belong in the prelude

Decision: the user requested Optional, Result, their related helpers, and Error without imports. The later accepted [issue #187 direction](https://github.com/manuscript-lang/manuscript/issues/187#issuecomment-6138072921) adds List and Map to that scope; Set uses the same mechanism. The latest direction removes existing imports and requires every type referenced by the public List/Map/Set API in the prelude. Its recursive nominal closure adds CollectionError, ListEntry, MapEntry, and MissingValue (through Optional.ok_or's default type argument); Optional, Result, Error, Equal, and Hashable already belong. Keep their canonical source-backed identities, including some/none, ok/error, and Optional receiver methods. Reject explicit imports by resolved canonical symbol identity with a binding-removal fix (MS2003). Project aliases to application types keep ordinary identity; renaming, reexports, and aliases that override the reserved @std directory remain unsupported. Ordinary declarations may select a local identity instead; a matching spelling must not acquire native behavior. Other standard APIs remain explicit imports. [Map.add is the accepted insertion spelling](https://github.com/manuscript-lang/manuscript/issues/187#issuecomment-6138104857); the older `with_entry` and alias spellings were removed (#358).

Reason: a spelling-only ban would reject application declarations, and duplicated support definitions would split native identities. An ambiguous unqualified `LimitExceeded` needs `CollectionError.LimitExceeded` or another explicit case owner; match patterns still resolve through their scrutinee. Recursive signature, type-argument default, and native receiver-bound tests guard future additions. MissingValue also makes `Missing` ambient; qualify an expression as `MissingValue.Missing` or another explicit owner when needed.

Apply when: changing prelude scope, standard imports, case lookup, or editor auto-imports.
Evidence: [module scope rules](../documentation/core-language/modules/declarations.md#names-and-declaration-order), [native prelude conformance](../tests/e2e/testdata/accept/prelude.ms), [case inference and shadowing regressions](../pkg/compiler/prelude_test.go), [collection execution](../tests/e2e/testdata/accept/collection-prelude.ms), [Set execution](../tests/e2e/testdata/accept/set-prelude.ms), and [editor completion/navigation](../pkg/tooling/lsp/completion_test.go).
Verify: Optional methods and Result propagation into Error execute without imports; incomplete constructors and ambiguous cases still fail; editor completion adds no redundant import and definitions reach pinned standard source.

### Parameterless main and imported host accessors

Decision: applications export `fn main() -> Int` and import the standard services they use. The user explicitly deferred enforcement; the earlier exploration of `using`, scoped replacement, and manifest permissions is not an accepted implementation requirement. Ordinary service parameters remain available for helpers and source fakes.

Apply when: changing entrypoints, host roots, standard imports, tests, or authority documentation.
Evidence: [CLI contract](../pkg/stdlib/cli.ms), [entry validation](../pkg/compiler/compiler.go), and [execution-local accessors](../pkg/runtime/host.go).
Verify: a parameterless entry runs; parameterized entries fail; imported accessors share roots across derived executions and imported helpers, while separate tests receive separate root wrappers.

### Keep short bodies available without a second function kind

Decision: the user requested a terse language with single-line functions and conditions. Do not restore the earlier blanket requirement for indented function bodies. The user clarified that `else` must start on a separate line: allow one branch per line, and reject same-line `else` or `else if`. The latest correction permits a single expression after a function or method colon and implicitly returns it. Multiline bodies retain explicit returns. Other inline suites retain ordinary statement semantics; there is no separate callable kind.

Apply when: changing suite parsing, anonymous-function layout, formatting, or syntax documentation.
Evidence: [canonical suite rules](../documentation/core-language/basics/grammar.md#statements-and-patterns), [parser boundary cases](../pkg/parser/parser_test.go), and [native inline conformance](../tests/e2e/testdata/accept/inline-suites.ms).
Verify: parse an inline callback inside a call without consuming the enclosing delimiter; execute inline and indented branches together; preserve formatting idempotence and reject multiple statements in an inline body.

### Read-only accessors are executable members with checked evidence

Decision: the approved migration uses one `get name -> T` member declaration for source, native and interface implementations. Reads are live and evaluate their receiver once; they retain mutable result aliases and ordinary effects. Read-only describes assignment to the member, not purity or a frozen result. `Error.message()` and every implementation remain methods, including bound method values. Keep the approved migration inventory closed rather than inferring new candidates from a zero-argument signature.

Verified: accessor kind must survive interface conformance, lexical implementation evidence and runtime dispatch identity. Native-looking interface types can have source implementations, so static helper selection must exclude contract dispatch. Scalar/tag reads preserve their representation; static reads do not manufacture bound callables. Accessor reads are execution edges for effects, recursion, `try` ordering, inspection and source breakpoints.

Apply when: changing members, interface evidence, native dispatch, accessor lowering or editor metadata.
Evidence: [canonical accessor rules](../documentation/core-language/types/contracts.md#read-only-accessors), [approved inventory](../documentation/contributing/read-only-accessors-design.md), [exact standard inventory and Error checks](../pkg/stdlib/accessors_test.go), [checked member rules](../pkg/checker/accessors_test.go), [emitted forms](../pkg/lower/lower_accessors_test.go), and [native source/interface semantics](../pkg/build/accessors_native_test.go).
Verify: read a side-effecting receiver once; observe later mutations and aliases; reject assignment and method/accessor conformance mismatches; execute source implementations of standard interfaces through concrete, generic and view paths; retain Error.message callable references.

### Optional values need presence accessors and extraction methods

Decision: the user explicitly rejected relying on `match` for routine Optional handling. Keep one receiver surface: `is_some`, `is_none`, `unwrap`, `unwrap_or`, and `unwrap_or_else`. The later approved accessor migration makes presence checks read-only accessors while extraction stays callable. Preserve Optional as an ordinary alternative with no flattening. The private native helpers are implementation bindings, not exported aliases.

Decision: the later request to accept `Queue[Int](capacity: 4)` permits a plain payload at standard Optional argument boundaries. Routine calls and current examples use plain values rather than redundant `some(...)` arguments. Keep this separate from omission permissions and ordinary assignment/return compatibility. Lower the supplied argument to a real `some` value so source implementations and native APIs receive the same representation; preserve written evaluation order and payload identity.

Apply when: changing Optional declarations, alternative method lookup, fallback evaluation, or introductory examples.
Evidence: [Optional contract](../documentation/core-language/types/optionals.md#checking-and-extracting-values), [optional argument rules](../documentation/core-language/types/optionals.md#passing-optional-arguments), [canonical declaration](../pkg/stdlib/optional.ms), [compiled method fixture](../tests/e2e/testdata/accept/optional-methods.ms), and [argument conformance](../tests/e2e/testdata/accept/optional-arguments.ms).
Verify: false and zero are present; eager defaults evaluate normally; lazy defaults run exactly once only for none; unwrap on none faults clearly. Extraction retains nested type arguments and payload identity, stored extraction methods still work, presence reads return Bool immediately, and local alternatives with the same spelling receive no native members.

Verified: Optional argument checking retains the expression's source type and records wrapping separately, so editor queries and Boolean folding keep their existing meaning. Reuse an inferred payload type before retrying with context: checking every nested call twice causes exponential work for both accepted and rejected inputs. Evidence: [source/AST regression](../pkg/checker/optional_test.go), [nested call regression](../pkg/compiler/optional_test.go), and [argument checking](../pkg/checker/calls.go). The same rule applies to successful independent generic argument checks: reuse their checked information within the owning call, then apply ordinary expected-type and conversion checks. Do not cache probes across calls or scopes. Contextual callback probes can be retained within their owning call only when their final function signature is identical and contains no unresolved inference variables; replay retained root diagnostics once. A complete result signature alone is insufficient: earlier unresolved or conflicting returns, and `try` checked before the enclosing result is known, can require the final context to repair a valid body. Record this dependence and recheck those bodies; invalid result slots can be reused only when the final signature retains exactly those slots. Evidence: [callback complexity and context regressions](../pkg/compiler/callback_work_test.go), [native callback metadata](../tests/e2e/testdata/accept/callback-probe-reuse.ms), and [issue #151](https://github.com/manuscript-lang/manuscript/issues/151). Evidence: [deep generic arguments](../pkg/compiler/inference_work_test.go) and [native order, conversions, and captures](../tests/e2e/testdata/accept/inference-call-order.ms).

### Recursive data uses references; generic applications still stay finite

Decision: direct and mutually recursive tree types, resolving [issue #97](https://github.com/manuscript-lang/manuscript/issues/97) and superseding the inline-layout restriction. Preserve complete initialization, reference aliasing, shallow cloning, and cycle-safe structural equality. Recursive shapes must not automatically derive Hashable: structural hashing has no cycle guard, while explicit domain identity implementations remain available.

Verified: declaration dependency cycles distinguish finite nesting such as `Box[Box[Int]]` from expanding generic recursion. Track generic substitutions around declaration cycles rather than recursively expanding storage layouts. The finite-application rule includes references in generic arguments, functions, and interface operations; indirect storage cannot hide an expanding type family. Collection identities are not user declaration cycles. Keep active cycle detection separate from completed equality/hashing results, so shared acyclic shapes do not trigger exponential property checking.

Apply when: changing recursive data, automatic equality/hashing, or generic regularity checks.
Evidence: [recursive data rules](../documentation/core-language/types/records.md#recursive-data), [declaration checks](../pkg/checker/type_recursion.go), [compiler regressions](../pkg/compiler/recursive_types_test.go), [shared-dependency regressions](../pkg/checker/layout_diagnostics_test.go), and [native recursive data fixture](../tests/e2e/testdata/accept/recursive-types.ms).
Verify: direct and mutual trees execute; cyclic equality terminates; clone retains child references; uninitialized self-references and automatic recursive hashing fail. Finite nested generic applications pass; expanding cycles through fields, callbacks, or interfaces fail.

### Match is uniformly a value expression; indexing preserves Optional

Decision: when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form. A standalone match discards the same checked result. The user also clarified that list brackets must preserve `.at()`'s Optional result, rather than unwrap or introduce bounds faults. Generic specialization retains its existing meaning.

Apply when: changing matching, collection lookup, type application parsing, or examples migrating from other languages.
Evidence: [match values](../documentation/core-language/control-flow/pattern-matching.md#arm-values), [list lookup](../documentation/core-language/types/collections.md#lookup-and-updates), and [native expression conformance](../tests/e2e/testdata/accept/expression-conveniences.ms).
Verify: use `items[index].unwrap_or(0)` for absent indexes, keep `identity[Int]` specialization, and exercise enclosing returns, propagation, cleanup, and loop exits from match arms. An effects-only arm ending in a value-returning call needs an explicit `unit` when another arm produces Unit.

### Infer local callback signatures from context

Decision: the user explicitly permits callback parameter and result inference. Known function contexts supply omitted parameter types; callback bodies can supply generic output evidence after inputs are known, including success types within a partially known Result context. Named public signatures stay explicit, and callable argument labels retain their existing function identity. Following [issue #81](https://github.com/manuscript-lang/manuscript/issues/81), contextual anonymous functions adopt the expected call labels independently of local parameter names; lowering must dispatch using those context labels while binding body names by position. Use existing argument/field defaults to omit redundant values; do not treat every Optional parameter as implicitly defaulted.

Decision: unambiguous generic inference from the expected result to address [issue #98](https://github.com/manuscript-lang/manuscript/issues/98), superseding the argument-only restriction. Preserve argument evidence and explicit specialization; use result context before deferred callbacks, without widening ordinary nominal/function types or adding Optional return wrapping. Existing Error boundaries retain concrete error evidence. Inferred function types still erase default omission permissions.

Verified: argument inference must apply Result error widening within each transactional match, including the single Optional payload attempt, and check the completed target after substitution. A separate root-only fallback missed Optional wrapping and an error parameter already determined as Error; committing a failed success prefix would constrain unrelated later evidence. Keep success types and nested applications invariant, then let final argument checking retain scoped Error evidence. Evidence: [conversion and rollback checks](../pkg/compiler/result_argument_inference_test.go), [native identity and order](../tests/e2e/testdata/accept/result-argument-inference.ms), and [local implementation boundaries](../tests/e2e/result_argument_scope_test.go).

Verify: source and native callbacks cover generic map results, callbacks listed before their inference inputs, optional callbacks, nested closures, constructors, and editor parameter navigation. Expected-result tests also cover return/binding contexts, bounds, conflicting evidence, concrete Error conversion, and nested call order. Preserve explicit annotations where incomplete Result construction or `try` lacks a known result context.

Apply when: changing callback checking, generic inference, syntax or editor annotations.
Evidence: [callback rules](../documentation/core-language/functions/function-values-and-closures.md#contextual-callback-inference), [acceptance and rejection checks](../pkg/compiler/callbacks_test.go), and [native fixture](../tests/e2e/testdata/accept/contextual-callbacks.ms). Expected-result evidence: [inference rules](../documentation/core-language/types/generics.md#inference-from-arguments), [compiler boundaries](../pkg/compiler/contextual_generics_test.go), [native execution](../tests/e2e/testdata/accept/contextual-generics.ms), and [editor information](../pkg/tooling/lsp/contextual_generics_test.go).

### Direct native calls must capture receivers before arguments

Verified: Go orders function calls left to right but does not guarantee that a plain variable argument is read before a later call. Replacing bound-method construction with `ListAt(ctx, receiver, indexExpression, ...)` let a match expression in the index reassign the receiver before it was captured. An inline `SourceAt` call captures the receiver first while preserving fault attribution; direct scalar lowering likewise extracts operands through calls.

Apply when: removing bound-call wrappers or lowering expressions directly to Go operations.
Evidence: [direct collection lowering](../pkg/lower/lower_collections.go), [receiver reassignment regression](../tests/e2e/testdata/accept/collection-call-order.ms), and [evaluation-order contract](../documentation/contributing/compiler/lowering/evaluation-order.md).
Verify: a list receiver initially containing 7 still returns 7 when its index expression reassigns the local to a list containing 9; receiver and argument expressions each execute once in written order.

### Module-level constants are use-site evaluations, not stored values

Decision: Chinmay approved top-level `let NAME[: T] = <constant expression>` in the #332 thread after the ban was found to have no recorded rationale; the inferred gains of the ban were no module initialization order, no startup side effects, and no shared module state. Constants keep those gains: a use evaluates the initializer, so list and map constants are fresh per use.
Verified: a constant is a parameterless `fn` marked `Declaration.Constant` whose body returns the initializer. The checker validates the constant-expression form, infers an unannotated type with cycle detection, and rewrites a constant name to a call marked `ConstantUse`; a written `NAME()` is rejected. Lowering, imports, and exports are unchanged. LSP hover, completion, outline, workspace symbols and semantic tokens, `ms inspect` entities and call sites, and docgen present a constant as a constant of its value type through `Symbol.IsConstant` and `Symbol.ValueType`; lowering, diagram labels and the Go output still see the function.
Open: hoisting scalar constants to Go constants for performance.

Apply when: changing top-level declarations, name resolution of module symbols, or the formatter's blank-line rules.
Evidence: [constants rules](../documentation/core-language/modules/declarations.md#constants), [checker](../pkg/checker/constants.go), [diagnostics](../tests/e2e/constants_test.go), and [native fixture](../tests/e2e/testdata/accept/constants.ms).
Verify: `ms run` on a module using an exported constant from another module, a local `let` shadowing a constant, and `A()` on a constant rejected.
