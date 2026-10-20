# Language lessons

Note on memory model: on 2026-10-19 the owner adopted value semantics for the Rust implementation (see [compiler.md](compiler.md) and [ownership notes](../crates/ms-check/OWNERSHIP.md)). Entries below that speak of shared references, aliasing, or `.clone()` record user decisions made under reference semantics; where they conflict with the ownership notes, the notes and the frozen conformance corpus win, and the conflict is flagged in the entry.

### Standard and user code share one method syntax

Decision: the user required that the standard library, as the reference, use only forms user code can write. Methods live in `impl` blocks, never in `type` bodies: `impl Type:` declares a type's own methods and `impl Interface for Type:` implements an interface; the presence of `for` fixes which name is the type, so no lookup is needed. Rejected spellings: `impl Type as/with/satisfies Interface`, a comma form, and a stdlib-only `native impl`. Method-level type parameters work only in bundled modules; source methods reject them, a known gap.

Apply when: changing impl parsing, method declaration rules, stdlib receiver operations, or docs that show type declarations with methods.
Evidence: [contract rules](../documentation/core-language/types/contracts.md#explicit-implementations), [parser](../crates/ms-syntax/src/parser.rs), [inherent method fixture](../tests/e2e/testdata/accept/inherent-methods.ms).
Verify: `fn` in a `type` body is a parse error; `impl Type:` works across modules for exported types; `impl Interface:`, `impl Foreign:`, and generic methods give targeted errors; `make conform` still binds every receiver operation.

### An unsaved overlay cannot replace a dangling source symlink

Decision: editor overlays may create a file beneath an existing confined directory, but a dangling symlink remains a filesystem entry whose target identity must be respected. Treating every not-found canonicalization result as an unsaved file would let an overlay hide an unresolved external target.

Apply when: changing project resolution, filesystem identity, or editor overlays.
Evidence: [overlay canonicalization](../crates/ms-project/src/overlay.rs), [symlink identity regression](../crates/ms-project/tests/project.rs).
Verify: new confined overlay files compile without being written to disk; overlays for outside paths, dangling external links, or symlinked external parents are rejected. Normalize accepted overlay keys to canonical file identity so symlinked workspace directories retain unsaved content; reject conflicting snapshots of one file. Recovery keeps valid declarations while diagnostics still prevent producing an executable.

### String conversion is available on every value

Decision: the user requested conversion with `to_string()` on everything. This supersedes the previous restriction of interpolation to scalars. Conversion is available in unconstrained generic code and uses the same representations as interpolation; ordinary type compatibility at assignment, call, and return boundaries remains explicit.

Apply when: changing interpolation, member resolution, formatting, or editor member queries.
Evidence: [canonical conversion rules](../documentation/core-language/basics/text-and-bytes.md#converting-values-to-string); [source conformance](../tests/e2e/testdata/accept/to-string.ms).
Verify: a record and an unconstrained `T` both support `.to_string()` and direct interpolation; a closed resource converts without invoking an operation; passing that record directly to a String parameter is still rejected.

### Invalid bounds must not survive recovery

Verified (a Go-era crash class; the invariant is language-level): reporting an invalid bound without removing it lets implementation substitution turn a variable bound into a self-referential graph. Diagnostic hints and editor member discovery must terminate even on malformed bound graphs. Keep valid interface bounds such as `T: Compare[T]`; reject variable bounds such as `T: T` without attaching them as evidence.

Apply when: resolving generic bounds, copying implementation variables, or traversing recovered types for diagnostics and editor queries.
Evidence: [recursive interface bound fixture](../tests/e2e/testdata/accept/recursive-interface-bound.ms).
Verify: a program with `T: T` reports a diagnostic and the checker and language server both terminate.

### Local implementations must remain selected across module boundaries

Verified: accepting an implementation for an imported source type requires more than relaxing receiver ownership. Extensions are limited to their declaring module; views, bound methods, cleanup, and generic specialization retain that selection at runtime. A global receiver/contract lookup would silently select another module's extension. Inherited receiver bounds also need their resolved nominal identities, rather than resolving their source spelling again in the extending module. Implementation details are in [compiler.md](compiler.md).

Apply when: changing implementation visibility, generic evidence, contract wrappers, cleanup dispatch, or editor member lookup.
Evidence: [coherence and visibility](../documentation/core-language/types/contracts.md#coherence-and-visibility); [cross-module dispatch project](../tests/e2e/testdata/projects/local_extensions/conformance_test.ms).
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

Verified: when rebasing standard-library work onto current main, migrate new conformance fixtures and documentation examples to ordinary `if not (...)` checks returning `panic`; do not restore the removed testing module or its native bindings from a stash. The source-level [built-in parity fixture](../tests/e2e/testdata/accept/builtin-parity.ms) exercises this form, and [standard bindings](../stdlib/bindings.json) remain free of the removed module.

### Error translation does not need a dedicated standard helper

Decision: remove the specialized Result error-mapping helper and keep domain translation in ordinary functions that test `is_error()` and read `err()`, never a `match`. The newer error simplification permits specific errors to pass directly into the standard Error boundary, including through `try`; unrelated domain errors still require explicit translation. Do not restore a dedicated mapping helper.

Decision: the user requested "please remove nested match from everywhere, note it as anti pattern and ensure it never gets repeated", then reaffirmed "nested match is anti pattern, solve it another way". This includes implementation, examples, documentation and diagnostic remedies. Keep grammar and execution semantics available for compatibility and meaningful syntax/semantic regressions. Use compatible `try`, early-exit payload bindings, Optional methods, or small helpers; the user also rejected elaborate loading examples, so avoid contrived domain models and helper layers added only to make an example work.

Verified: MSL107 warns at each structurally inner match ([match lint](../crates/ms-tooling/src/lint/matches.rs)); the [repository guard](../crates/ms-repo-check/src/nested.rs) inspects sources and Markdown fences, and test allowances are scoped and require a reason. MSL106 belongs to the payload-binding rule ([binding lint](../crates/ms-tooling/src/lint/bindings.rs)); take new rule codes from the actual lint registry, not from an earlier completion report.

Apply when: adding Result adapters or rewriting examples that combine execution and domain errors.
Evidence: [flat flow and grammar compatibility](../documentation/core-language/control-flow/pattern-matching.md#keep-match-flow-flat); [error compatibility](../documentation/core-language/errors/propagation.md#error-compatibility).
Verify: examples compile with compatible `try` calls and introduce only the concepts they teach. Result's success-only `map` and same-error `and_then` retain the original error payload; they do not add an error-translation helper. The standard Result module exports only its type, and regenerated API references agree with its declarations. [Called composition tests](../tests/e2e/testdata/stdlib/core-parity.ms) distinguish success transformation from error translation.

### Equality and hashing are source interfaces

Decision: the stdlib revamp explicitly replaces compiler-only equality/hashing bounds with `Equal` and `Hashable` interfaces, and explicit implementations select domain identity. Custom equality requires an explicit consistent hash before the type becomes a key; structural hashing cannot silently use different fields. (The revamp kept reference semantics at the time; the value-semantics decision changes aliasing, not key identity.)

Apply when: changing equality operators, generic bounds, contract views, key lookup, or implementation visibility.
Evidence: [equality rules](../documentation/core-language/types/equality-and-hashing.md), [source interfaces](../stdlib/equality.ms), and [compiled domain-key fixture](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: two keys with equal IDs and different labels compare equal and occupy one map entry; an equality override without a hash is rejected as a map key. Keep local implementation selection when forwarding generic arguments.

Decision: all values may be passed freely, and closures have ordinary captures. Concurrency and shared-state guards were removed pending a ground-up redesign. (Under value semantics, closure capture is by borrow or move; see the ownership notes.)

### Compound assignment, counting ranges, and redundant labels

Decision: the user asked to add `+= -= *= /= %=`, a step-1 `range(start, end)`, and removal of redundant argument labels (October 2026 proposal `structural-syntax`), reversing the earlier MS1000 rejection of compound assignment. A compound statement means `target = target op (value)` with the written operator kept for formatting; the receiver of a field target must be names only so it is read once. `range(start, end)` returns `List[Int]` and `for x in range(a, b)` is a counter loop with bounds evaluated once; the stepped, fallible form is `range_by`. The formatter cannot know parameter order, so label removal is the checked `ms fmt --drop-labels`, never part of plain `ms fmt`. Provable-bounds `[]` narrowing was already merged in #555 and later removed (see the indexing entry).

Apply when: changing assignment syntax, `for` lowering, `@std/collections.ms` factories, or the formatter.
Evidence: [native fixture](../tests/e2e/testdata/accept/compound-assignment.ms), [range fixture](../tests/e2e/testdata/stdlib/collections.ms).
Verify: `total -= a - b` subtracts the whole right side, a call or index receiver is rejected, a `range` bound mutated in the body does not change the count, and `--drop-labels` is idempotent and skips labels that select another parameter.

### Syntax improvements need examples across their boundaries

Decision: support grouped symbol imports and brace Map literals. The user's newer explicit request to "remove mandatory labels for invoking functions" supersedes the prior restriction to single-parameter unlabeled calls. Invocation labels are optional across functions, methods, function values and constructors. Superseded by issue #452 (user direction): an unlabeled argument, including a bare identifier, is always positional and never selects a parameter by its spelling; only `name: value` selects by name. Matching-name shorthand and its MSL109 advisory were removed (MSL109 is now the Result two-arm match advisory). Keep callback function-type label identity separate from invocation syntax, including the contextual-lambda label adoption rule.

Apply when: changing calls, grammar, inference or editor assistance.
Evidence: [canonical call rules](../documentation/core-language/functions/declarations-and-calls.md#argument-names); [native calls](../tests/e2e/testdata/accept/positional-arguments.ms).
Verify: positional/labeled/mixed calls bind deterministically, a bare identifier fills the next unfilled slot whatever its name, supplied values execute once in written order before defaults, and callback mismatched names remain rejected. Editor rename adds no labels, since a rename can no longer change binding.

### Recover concrete contract receivers through checked matching

Decision: a common Error contract must allow generic diagnostics and specific handling without discarding the concrete error. The user requested constructing errors once and passing them directly into the root Error interface. An explicit implementation establishes the relationship; assignments, arguments, returns, Result error widening, and `try` can use it without a written view conversion. Ordinary domain fields contain typed details. Unrelated domains and other interfaces retain exact compatibility. Contract matches use concrete record/alternative type patterns with exactly one receiver binding and a final wildcard for other implementations.

Verified: direct or stored standard error `message` methods dispatch through the registered Error implementation, rather than intrinsic receiver dispatch. Receiver type parameters belong to the implementation, not method-level inference. The [compiled error fixture](../tests/e2e/testdata/accept/library-errors.ms) exercises direct and stored diagnostics alongside generic error views.

Apply when: changing Error boundaries, contract views, matching, or native standard implementations.
Evidence: [contract type patterns](../documentation/core-language/control-flow/pattern-matching.md#contract-type-patterns); [common error boundary](../documentation/core-language/errors/results.md#a-common-error-boundary); [compiled errors and generic patterns](../tests/e2e/testdata/accept/library-errors.ms).
Verify: exact nominal identities and generic arguments determine a match; the receiver and payload survive conversion and propagation; missing implementations, incomplete generic patterns, and missing fallbacks are rejected.

### Default arguments must not leak across callable replacement

Decision: ordinary record fields may have default expressions. Constructors evaluate supplied arguments before omitted defaults in field order, with earlier fields available to later defaults; explicit values skip defaults and each construction evaluates fresh storage. A source function's default is evaluated in the callee's scope, so it can read earlier parameters. The user explicitly requires standard runtime functions to appear as syntactically correct empty functions, with their full declarations and ordinary colon headers; do not introduce a `native` keyword or hide invalid syntax in editor analysis. Evidence: [record construction rules](../documentation/core-language/types/records.md#construction), [field-default conformance](../tests/e2e/testdata/accept/field-defaults.ms).

Verified: defaults are permissions on a known callable, not part of function-type identity. Retaining that permission on a mutable binding or inferred generic type could let a required-argument function replace a defaulted function, then be called with a missing argument. Explicit function types, mutable bindings, and generic inference erase defaults; inferred immutable copies retain them.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../documentation/core-language/functions/declarations-and-calls.md#default-arguments); [native default behavior](../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.

### Mutable data uses explicit copying

Decision (user, under reference semantics): ordinary record fields and collections are mutable. The user rejected immutable replacement APIs and instance freezing in favor of an explicit duplicate operation (`.clone()`). Preserve `let`/`var` binding rules independently of object mutation. Do not manufacture copies of sockets, files, locks, or other native service handles.

Superseded in part: under value semantics `let` is deeply immutable, aliasing is gone, `.clone()` is deep and is being renamed `.copy()`, and resources are move-only and never copied. The statements that aliases observe mutation, that a clone's nested references stay shared, and that a cloned record may retain a handle reference no longer hold. Treat [ownership notes](../crates/ms-check/OWNERSHIP.md) as authoritative; fixtures tagged `aliasing` in the conformance corpus are excluded for this reason.

Apply when: changing fields, collection updates, copies, or equality.
Evidence: [record contract](../documentation/core-language/types/records.md#mutation-and-cloning); [collection contract](../documentation/core-language/types/collections.md#mutation-and-copies); [mutation fixture](../tests/e2e/testdata/accept/mutation.ms); [ownership notes](../crates/ms-check/OWNERSHIP.md).
Verify: the counter's Unit-returning method updates `self.val`; a `.copy()` is independent of its source; copying a native resource is rejected. Do not restore removed sharing bounds.

### Source-backed data types belong in the prelude

Decision: the user requested Optional, Result, their related helpers, and Error without imports. The later accepted [issue #187 direction](https://github.com/manuscript-lang/manuscript/issues/187#issuecomment-6138072921) adds List and Map to that scope; Set uses the same mechanism. The latest direction removes existing imports and requires every type referenced by the public List/Map/Set API in the prelude. Its recursive nominal closure adds CollectionError, ListEntry, MapEntry, and MissingValue (through Optional.ok_or's default type argument); Optional, Result, Error, Equal, and Hashable already belong. Keep their canonical source-backed identities, including some/none, ok/error, and Optional receiver methods. Reject explicit imports by resolved canonical symbol identity with a binding-removal fix (MS2003). Project aliases to application types keep ordinary identity; renaming, reexports, and aliases that override the reserved @std directory remain unsupported. Round 2 bug bash (user decision): declarations and application imports that reuse a prelude type name or some/none/ok/error are rejected ("reuses a prelude name") instead of selecting a local identity, because shadowing produced confusing follow-on errors. Other standard APIs remain explicit imports. [Map.add is the accepted insertion spelling](https://github.com/manuscript-lang/manuscript/issues/187#issuecomment-6138104857); the older `with_entry` and alias spellings were removed (#358).

Reason: a spelling-only ban would reject application declarations, and duplicated support definitions would split native identities. An ambiguous unqualified `LimitExceeded` needs `CollectionError.LimitExceeded` or another explicit case owner; match patterns still resolve through their scrutinee. MissingValue also makes `Missing` ambient; qualify an expression as `MissingValue.Missing` or another explicit owner when needed.

Apply when: changing prelude scope, standard imports, case lookup, or editor auto-imports.
Evidence: [module scope rules](../documentation/core-language/modules/declarations.md#names-and-declaration-order), [prelude conformance](../tests/e2e/testdata/accept/prelude.ms), [collection execution](../tests/e2e/testdata/accept/collection-prelude.ms), [Set execution](../tests/e2e/testdata/accept/set-prelude.ms), [prelude import resolution](../crates/ms-check/src/prelude_imports.rs).
Verify: Optional methods and Result propagation into Error execute without imports; incomplete constructors and ambiguous cases still fail; editor completion adds no redundant import and definitions reach standard source.

### Parameterless main and imported host accessors

Decision: applications export `fn main() Int` and import the standard services they use. The user explicitly deferred enforcement; the earlier exploration of `using`, scoped replacement, and manifest permissions is not an accepted implementation requirement. Ordinary service parameters remain available for helpers and source fakes.

Apply when: changing entrypoints, host roots, standard imports, tests, or authority documentation.
Evidence: [CLI contract](../stdlib/process.ms), [host accessors fixture](../tests/e2e/testdata/accept/host-accessors.ms).
Verify: a parameterless entry runs; parameterized entries fail; imported accessors share roots across derived executions and imported helpers, while separate tests receive separate root wrappers.

### Keep short bodies available without a second function kind

Decision: the user requested a terse language with single-line functions and conditions. Do not restore the earlier blanket requirement for indented function bodies. The user clarified that `else` must start on a separate line: allow one branch per line, and reject same-line `else` or `else if`. The latest correction permits a single expression after a function or method colon and implicitly returns it. Multiline bodies retain explicit returns. Other inline suites retain ordinary statement semantics; there is no separate callable kind.

Apply when: changing suite parsing, anonymous-function layout, formatting, or syntax documentation.
Evidence: [canonical suite rules](../documentation/core-language/basics/grammar.md#statements-and-patterns), [inline suite fixture](../tests/e2e/testdata/accept/inline-suites.ms).
Verify: parse an inline callback inside a call without consuming the enclosing delimiter; execute inline and indented branches together; preserve formatting idempotence and reject multiple statements in an inline body.

### Optional values need presence and extraction methods

Decision: the user explicitly rejected relying on `match` for routine Optional handling. Keep one receiver surface: `is_some`, `is_none`, and `get(default)`; `or_else` takes a lazy Optional fallback. `unwrap`, `unwrap_or`, `unwrap_or_else`, `unwrap_error`, and `at` are removed (Result keeps `get(default)`, `or_else`, `err`). Preserve Optional as an ordinary alternative; these methods do not introduce flattening or new syntax. The private native helpers are implementation bindings, not exported aliases.

### No special `get` accessor declarations

Decision: the user rejected the `get name -> Type` accessor syntax merged in #516 (2026-10-16) and asked for ordinary members: observational reads such as `length` are methods called as `items.length()`. Do not reintroduce a second member category, contextual keyword, or accessor-specific dispatch without a new decision. The speed motivation is met in lowering instead: a List or Bytes `length()` call is lowered directly rather than through a runtime call.

Apply when: proposing property-like syntax, a read-only member kind, or a standard-library migration from methods to properties.
Evidence: [native member lowering](../crates/ms-lower/src/native.rs), which special-cases `length` on List and Bytes.
Verify: `get` is an ordinary identifier everywhere; a List `length()` call involves no runtime function call.

Decision: the later request to accept `Queue[Int](capacity: 4)` permits a plain payload at standard Optional argument boundaries. Routine calls and current examples use plain values rather than redundant `some(...)` arguments. Keep this separate from omission permissions and ordinary assignment/return compatibility. Lower the supplied argument to a real `some` value so source implementations and native APIs receive the same representation; preserve written evaluation order and payload identity.

Decision: the user asked for `if let name = optional:` (with `else`) and that a match with only two arms is an anti-pattern. `if let` unwraps an Optional (present) or a Result (ok, error not captured; extended by a later request); the binding is immutable and scoped to the then-branch. MSL108 advises on Optional matches whose only arms are some and none, and MSL109 on Result matches whose only arms are ok and error; user alternatives are not covered. Decision (Chinmay, after #587): show no `match` as a way to unwrap a Result anywhere (docs, examples, stdlib, fixtures that are not testing pattern semantics): use `try`, `if let`, `get(default)`, or `is_ok`/`is_error`/`err`. Stdlib sources use `if let`; accepted conformance fixtures keep their some/none matches because they exercise match-expression semantics.

Apply when: changing Optional declarations, alternative method lookup, fallback evaluation, or introductory examples.
Evidence: [if let rules](../documentation/core-language/control-flow/conditionals.md#unwrapping-an-optional-or-result), [if let fixture](../tests/e2e/testdata/accept/if-let.ms), [two-arm match lint](../crates/ms-tooling/src/lint/matches.rs), [Optional contract](../documentation/core-language/types/optionals.md#checking-and-extracting-values), [optional argument rules](../documentation/core-language/types/optionals.md#passing-optional-arguments), [canonical declaration](../stdlib/optional.ms), [method fixture](../tests/e2e/testdata/accept/optional-methods.ms), [argument fixture](../tests/e2e/testdata/accept/optional-arguments.ms).
Verify: false and zero are present; eager `get(default)` values evaluate normally; `or_else` callbacks run exactly once only for none; `get()` with no default on none or error faults clearly. Extraction retains nested type arguments and payload identity, stored receiver methods still work, and local alternatives with the same spelling receive no native methods.

Verified: Optional argument checking retains the expression's source type and records wrapping separately, so editor queries and Boolean folding keep their existing meaning. Reuse an inferred payload type before retrying with context: checking every nested call twice causes exponential work for both accepted and rejected inputs. The same rule applies to successful independent generic argument checks: reuse their checked information within the owning call, then apply ordinary expected-type and conversion checks. Do not cache probes across calls or scopes. Contextual callback probes can be retained within their owning call only when their final function signature is identical and contains no unresolved inference variables; replay retained root diagnostics once. A complete result signature alone is insufficient: earlier unresolved or conflicting returns, and `try` checked before the enclosing result is known, can require the final context to repair a valid body. Record this dependence and recheck those bodies; invalid result slots can be reused only when the final signature retains exactly those slots. Evidence: [callback probe fixture](../tests/e2e/testdata/accept/callback-probe-reuse.ms), [inference call order](../tests/e2e/testdata/accept/inference-call-order.ms), and [issue #151](https://github.com/manuscript-lang/manuscript/issues/151).

### Recursive data; generic applications still stay finite

Decision: direct and mutually recursive tree types, resolving [issue #97](https://github.com/manuscript-lang/manuscript/issues/97) and superseding the inline-layout restriction. Preserve complete initialization and cycle-safe structural equality. Recursive shapes must not automatically derive Hashable: structural hashing has no cycle guard, while explicit domain identity implementations remain available. Open: the original decision also required reference aliasing and shallow cloning for recursive nodes; reconcile that with value semantics (indirection, `.copy()`) in the ownership notes before relying on it.

Verified: declaration dependency cycles distinguish finite nesting such as `Box[Box[Int]]` from expanding generic recursion. Track generic substitutions around declaration cycles rather than recursively expanding storage layouts. The finite-application rule includes references in generic arguments, functions, and interface operations; indirect storage cannot hide an expanding type family. Collection identities are not user declaration cycles. Keep active cycle detection separate from completed equality/hashing results, so shared acyclic shapes do not trigger exponential property checking.

Apply when: changing recursive data, automatic equality/hashing, or generic regularity checks.
Evidence: [recursive data rules](../documentation/core-language/types/records.md#recursive-data), [declaration cycle pass](../crates/ms-check/src/recursion.rs), and [recursive data fixture](../tests/e2e/testdata/accept/recursive-types.ms).
Verify: direct and mutual trees execute; cyclic equality terminates; uninitialized self-references and automatic recursive hashing fail. Finite nested generic applications pass; expanding cycles through fields, callbacks, or interfaces fail.

### Match is uniformly a value expression; indexing returns the element

Decision: when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form. A standalone match discards the same checked result. The earlier decision that brackets preserve `.at()`'s Optional result was reversed: `at` is removed, `[]` returns `T` and faults out of range, and `get(index, default: ...)` on List, String, and Bytes returns `T` or the default. Generic specialization retains its existing meaning. The flow-sensitive bounds proof (#552) only narrowed the type while the read still faulted, so it was removed; reintroducing bounds-check elimination needs its own proof.

Apply when: changing matching, collection lookup, type application parsing, or examples migrating from other languages.
Evidence: [match values](../documentation/core-language/control-flow/pattern-matching.md#arm-values), [list lookup](../documentation/core-language/types/collections.md#lookup-and-updates), and [expression conformance](../tests/e2e/testdata/accept/expression-conveniences.ms).
Verify: use `items.get(index, default: 0)` for absent indexes, keep `identity[Int]` specialization, and exercise enclosing returns, propagation, cleanup, and loop exits from match arms. Out-of-range `[]` faults with the index and length. An effects-only arm ending in a value-returning call needs an explicit `unit` when another arm produces Unit.

### Infer local callback signatures from context

Decision: the user explicitly permits callback parameter and result inference. Known function contexts supply omitted parameter types; callback bodies can supply generic output evidence after inputs are known, including success types within a partially known Result context. Named public signatures stay explicit, and callable argument labels retain their existing function identity. Following [issue #81](https://github.com/manuscript-lang/manuscript/issues/81), contextual anonymous functions adopt the expected call labels independently of local parameter names; lowering must dispatch using those context labels while binding body names by position. Use existing argument/field defaults to omit redundant values; do not treat every Optional parameter as implicitly defaulted.

Decision: unambiguous generic inference from the expected result to address [issue #98](https://github.com/manuscript-lang/manuscript/issues/98), superseding the argument-only restriction. Preserve argument evidence and explicit specialization; use result context before deferred callbacks, without widening ordinary nominal/function types or adding Optional return wrapping. Existing Error boundaries retain concrete error evidence. Inferred function types still erase default omission permissions.

Verified: argument inference must apply Result error widening within each transactional match, including the single Optional payload attempt, and check the completed target after substitution. A separate root-only fallback missed Optional wrapping and an error parameter already determined as Error; committing a failed success prefix would constrain unrelated later evidence. Keep success types and nested applications invariant, then let final argument checking retain scoped Error evidence. Evidence: [native identity and order](../tests/e2e/testdata/accept/result-argument-inference.ms) and [error widening](../tests/e2e/testdata/accept/result-error-widening-inference.ms).

Verify: source and native callbacks cover generic map results, callbacks listed before their inference inputs, optional callbacks, nested closures, constructors, and editor parameter navigation. Expected-result tests also cover return/binding contexts, bounds, conflicting evidence, concrete Error conversion, and nested call order. Preserve explicit annotations where incomplete Result construction or `try` lacks a known result context.

Apply when: changing callback checking, generic inference, syntax or editor annotations.
Evidence: [callback rules](../documentation/core-language/functions/function-values-and-closures.md#contextual-callback-inference), [contextual callbacks fixture](../tests/e2e/testdata/accept/contextual-callbacks.ms). Expected-result evidence: [inference rules](../documentation/core-language/types/generics.md#inference-from-arguments), [contextual generics fixture](../tests/e2e/testdata/accept/contextual-generics.ms), and [inference module](../crates/ms-check/src/inference.rs).

### Module-level constants are use-site evaluations, not stored values

Decision: Chinmay approved top-level `let NAME[: T] = <constant expression>` in the #332 thread after the ban was found to have no recorded rationale; the gains of the ban were no module initialization order, no startup side effects, and no shared module state. Constants keep those gains: a use evaluates the initializer, so list and map constants are fresh per use.

Verified (design, from the retired implementation): a constant is a parameterless function whose body returns the initializer. The checker validates the constant-expression form, infers an unannotated type with cycle detection, and rewrites a constant name to a call; a written `NAME()` is rejected. Imports and exports are unchanged. Editor hover, completion, outline, symbols, semantic tokens, `ms inspect`, and docgen present a constant as a constant of its value type, not as a function.
Open: hoisting scalar constants to compile-time values for performance.

Apply when: changing top-level declarations, name resolution of module symbols, or the formatter's blank-line rules.
Evidence: [constants rules](../documentation/core-language/modules/declarations.md#constants), [constant checking](../crates/ms-check/src/constants.rs), and [constants fixture](../tests/e2e/testdata/accept/constants.ms).
Verify: `ms run` on a module using an exported constant from another module, a local `let` shadowing a constant, and `A()` on a constant rejected.

### Pipe steps desugar in the parser; a leading `.` or `|` line continues a statement

Decision: Chinmay chose `|` (not `|>`, `?`, UFCS, or `map_error`) to compose free functions and `try` steps without temporaries; `|` earlier rejected as a second spelling for method chaining, but free functions had no flow form. Method chains use `| .m()`, and a bare `| try` unwraps the value so far.
Verified: the parser rewrites each step to the plain call or `try` it names, so checking, lowering and diagnostics are unchanged and argument order is the written order (the step head is a name path with no calls). The lexer treats a line starting with `|`, or `.` not followed by a digit or `.`, as a statement continuation indented exactly four spaces past the statement; no valid program started a line with either, so nothing existing changed meaning. A `.member` after a step applies to the step's result, and an operator after a pipe needs parentheses (the parser's diagnostic says so).

Apply when: changing operator precedence, line layout, `try`, or call argument binding.
Evidence: [pipe flows](../documentation/core-language/basics/expressions.md#pipe-flows), [parser](../crates/ms-syntax/src/parser.rs), and [pipe fixture](../tests/e2e/testdata/accept/pipe-flow.ms).
Verify: `try parse(text) | double | try check | .to_string_radix(radix: 10)` runs; a continuation line at the wrong indentation is rejected.

### Result types are written without `->`

Decision: the user asked to drop `->` before result types to save tokens (about 1% of source tokens measured with cl100k over the stdlib, accept tests, and examples; colons and `name: Type` were left alone). Named functions, methods, interface operations, and fn types still require the result type (`fn f(x: Int) Int:`, `fn(value: Int) Int`); lambdas may omit it and the parser reads a type after `)` as the result type and `:` as the body. `->` is a lexer token only so the parser can say to remove it. Call labels, map entries, and inline suites keep `:` because no separator would make `f(a [1])`, `a (b)`, and `a -1` unambiguous. `ms fmt` reformats migrated files because shorter lines rewrap.

Decision: the same spelling applies to displayed types, including LSP hover. Keep the shared type formatter ([types](../crates/ms-check/src/types.rs)) consistent with source syntax; hover, completions, diagnostics, and API snapshots consume it. Consumers that parse displayed signatures must skip nested callback parameter lists before reading the outer result.

Apply when: changing function type syntax, displayed signatures, or anything that parses a displayed type.
Evidence: [grammar](../documentation/core-language/basics/grammar.md).
Verify: a callback returning a Result inside a function that does not return one is extracted with the outer result, not the callback's.

### Result's error type is bounded by Error

Decision: Chinmay required `Result[T, E: Error]`; arbitrary error values (`String`, `Int`, collections) are rejected. Plain text uses `TextError("message")` and domain errors declare `impl Error`. Generic helpers over Result write `E: Error`.

Verified: the bound lives on `Result` in `stdlib/result.ms`, so annotations and inferred call results (including `Optional.ok_or`) hit the ordinary type-argument bound check. Native declaration default bounds (`ok_or[E: Error = MissingValue]`) are checked after standard impls bind.

Apply when: adding Result-returning APIs, examples, or tests that need an error value.
Evidence: [Result source](../stdlib/result.ms), [results guide](../documentation/core-language/errors/results.md).
Verify: `Result[Int, String]` fails with "String does not satisfy Error"; `Result[Int, TextError]` and `Result[T, Error]` pass.

### Grouped bindings are one-kind blocks, not tuple patterns

Decision: `let (` / `var (` declare several bindings of one kind, one entry per line, closing `)` aligned with the keyword; each entry is an ordinary binding (annotation or destructuring allowed) and sees earlier entries. Parenthesized patterns such as `let (a, b) = value` remain rejected, so a grouped block and a tuple pattern must stay distinguishable by the token after the keyword.

Apply when: changing binding grammar, formatter layout of declarations, or destructuring.
Evidence: [grouping rules](../documentation/core-language/basics/bindings.md#grouping-bindings), [destructuring](../documentation/core-language/types/destructuring.md), [module constants](../documentation/core-language/modules/declarations.md), [binding groups fixture](../tests/e2e/testdata/accept/binding-groups.ms).
Verify: `let (` entries evaluate in order with earlier ones in scope, `export let (` exports every entry, and `let (a, b) = pair` still fails with the not-a-binding-pattern diagnostic.
