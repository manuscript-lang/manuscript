# Language lessons

### An unsaved overlay cannot replace a dangling source symlink

Verified: editor overlays may create a file beneath an existing confined directory, but a dangling symlink remains a filesystem entry whose target identity must be respected. Treating every `EvalSymlinks` not-found result as an unsaved file allowed an overlay to hide an unresolved external target. Source path resolution now rejects that fallback for existing entries.

Apply when: changing project resolution, filesystem identity, or editor overlays.
Evidence: [source path resolution](../pkg/project/paths.go), [symlink/overlay regressions](../pkg/project/project_test.go), and [strict versus recovery compilation](../pkg/compiler/metadata_test.go).
Verify: new confined overlay files compile without being written to disk; overlays for outside paths, dangling external links, or symlinked external parents are rejected. Normalize accepted overlay keys to canonical file identity so symlinked workspace directories retain unsaved content; reject conflicting snapshots of one file. Recovery keeps valid declarations while diagnostics still prevent generated executable source.

### String conversion is available on every value

Decision: the user requested JavaScript-like conversion with `toString()` on everything. This supersedes the previous restriction of interpolation to scalars. Conversion is available in unconstrained generic code and uses the same representations as interpolation; ordinary type compatibility at assignment, call, and return boundaries remains explicit.

Apply when: changing interpolation, member resolution, formatting, or editor member queries.
Evidence: [canonical conversion rules](../documentation/core-language/basics/text-and-bytes.md#converting-values-to-string); [native source conformance](../tests/e2e/testdata/accept/to-string.ms); [opaque and cyclic formatting checks](../pkg/runtime/format_test.go).
Verify: a record and an unconstrained `T` both support `.toString()` and direct interpolation; a closed resource converts without invoking an operation; passing that record directly to a String parameter is still rejected.

### Local implementations must remain selected across module boundaries

Verified: accepting an implementation for an imported source type requires more than relaxing receiver ownership. The checker limits extensions to their declaring module; views, bound methods, cleanup, and generic specialization retain that selection at runtime. A global receiver/contract lookup would silently select another module's extension. Inherited receiver bounds also need their resolved nominal identities, rather than resolving their source spelling again in the extending module.

Apply when: changing implementation visibility, generic evidence, contract wrappers, cleanup dispatch, or editor member lookup.
Evidence: [coherence and visibility](../documentation/core-language/types/contracts.md#coherence-and-visibility); [boundary and inherited-bound checks](../pkg/compiler/local_extensions_test.go); [native cross-module dispatch fixture](../tests/e2e/testdata/projects/local_extensions/main.ms); [editor visibility and navigation](../pkg/tooling/lsp/completion_test.go).
Verify: two modules implement the same imported pair with different results; returned views and specialized functions retain their results, while raw values do not acquire either extension in a third module. Forwarding a generic argument must not change dispatch on statically concrete receivers in the callee.

### Read the current decision before restoring an older design

Decision: the language rebuild was directed to use the new design on `main`. Earlier designs and assistant proposals can conflict with subsequent user corrections. Establish the target contract from the latest direction and canonical pages before borrowing old implementation ideas.

Apply when: rebuilding a feature, reusing historical code, or reconciling branches.
Evidence: [user correction in Build out the language](codex://threads/01a12c08-60dd-731b-a496-4a932d9b6000); [design index](../documentation/_index.md).
Verify: the accepted/rejected source cases agree with the intended design, and any checkout mismatch is identified before being treated as a rule.

### Removing a construct includes its surrounding APIs

Decision: the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests. The user wanted ordinary `if`/`return` control flow. Removing the syntax alone did not satisfy the requested surface.

Apply when: removing or renaming language constructs or standard APIs.
Evidence: [successive corrections in Remove assert; use if return](codex://threads/01a12e19-ae70-752b-8c66-be8d59177006).
Verify: inventory related exported helpers and aliases before editing, regenerate references, then check every surface covered by the removal request. Follow an explicit zero-reference request when deciding whether rejection tests should retain the old spelling.

Verified: when rebasing standard-library work onto current main, migrate new conformance fixtures and documentation examples to ordinary `if not (...)` checks returning `panic`; do not restore the removed testing module or its native bindings from a stash. The source-level [built-in parity fixture](../tests/e2e/testdata/accept/builtin-parity.ms) exercises this form, and [standard bindings](../pkg/stdlib/bindings.json) remain free of the removed module.

### Error translation does not need a dedicated standard helper

Decision: remove the specialized Result error-mapping helper and keep domain translation in ordinary functions and matching. The newer error simplification permits specific errors to pass directly into the standard Error boundary, including through `try`; unrelated domain errors still require explicit translation. Do not restore a dedicated mapping helper.

Decision: the user rejected both deeply nested Result matches and the elaborate loading examples added to replace them. Keep examples small and focused on the concept being taught. Use compatible `try` calls for a flat success path; do not build contrived domain models or helper layers just to make an example work.

Apply when: adding Result adapters or rewriting examples that combine execution and domain errors.
Evidence: the user's removal request; [error compatibility](../documentation/core-language/errors/propagation.md#error-compatibility); [task group example](../documentation/concurrency/task-groups.md).
Verify: examples compile with compatible `try` calls and introduce only the concepts they teach. The standard Result module exports only its type, and regenerated API references agree with its declarations.

### Equality and hashing are source interfaces

Decision: the stdlib revamp explicitly replaces compiler-only equality/hashing bounds with `Equal` and `Hashable` interfaces. Built-in data keeps its value semantics, and explicit implementations select domain identity. Custom equality requires an explicit consistent hash before the type becomes a key; structural hashing cannot silently use different fields.

Apply when: changing equality operators, generic bounds, contract views, key lookup, or implementation visibility.
Evidence: [equality rules](../documentation/core-language/types/equality-and-hashing.md), [source interfaces](../pkg/stdlib/equality.ms), and [compiled domain-key fixture](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: two keys with equal IDs and different labels compare equal and occupy one map entry; an equality override without a hash is rejected as a map key. Keep local implementation selection when forwarding generic arguments.

Decision: all values may be passed freely; shared mutable state uses Synchronized, and closures have ordinary captures. This remains independent of equality, hashing, cleanup, and work lifetime.
Evidence: [sharing rules](../documentation/concurrency/sharing.md).

### Syntax improvements need examples across their boundaries

Decision: support grouped symbol imports, and allow an omitted call label for a function with one parameter while requiring labels for functions with more than one parameter. The single-parameter request measures declaration arity, not the number of arguments supplied. These are user decisions; verify their availability in the branch being changed.

Apply when: changing imports, calls, grammar, or editor assistance.
Evidence: [grouped-import request](codex://threads/01a12e1a-7d2d-7646-b5fc-2dc8fdd60038); [single-parameter request](codex://threads/01a12e4a-98e8-775e-9e6c-c101a8ac300d).
Verify: grouped imports resolve each symbol and its editor location; one-parameter calls exercise both spellings, multi-parameter calls require labels, and missing arguments still fail. Consult current grammar and compatibility rules for methods, constructors, and function values rather than assuming identical boundaries.

### Recover concrete contract receivers through checked matching

Decision: a common Error contract must allow generic diagnostics and specific handling without discarding the concrete error. The user requested constructing errors once and passing them directly into the root Error interface. An explicit implementation establishes the relationship; assignments, arguments, returns, Result error widening, and `try` can use it without a written view conversion. Ordinary domain fields contain typed details. Unrelated domains and other interfaces retain exact compatibility. Contract matches use concrete record/alternative type patterns with exactly one receiver binding and a final wildcard for other implementations.

Verified: direct or stored standard error `message` methods dispatch through the registered Error implementation, rather than intrinsic receiver dispatch. Receiver type parameters belong to the implementation, not method-level inference. The [compiled error fixture](../tests/e2e/testdata/accept/library-errors.ms) exercises direct and stored diagnostics alongside generic error views.

Apply when: changing Error boundaries, contract views, matching, or native standard implementations.
Evidence: [contract type patterns](../documentation/core-language/control-flow/pattern-matching.md#contract-type-patterns); [common error boundary](../documentation/core-language/errors/results.md#a-common-error-boundary); [compiled errors and generic patterns](../tests/e2e/testdata/accept/library-errors.ms); [invalid contract patterns](../pkg/compiler/library_test.go).
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

### Parameterless main and imported host accessors

Decision: applications export `fn main() -> Int` and import the standard services they use. The user explicitly deferred enforcement; the earlier exploration of `using`, scoped replacement, and manifest permissions is not an accepted implementation requirement. Ordinary service parameters remain available for helpers and source fakes.

Apply when: changing entrypoints, host roots, standard imports, tests, or authority documentation.
Evidence: [CLI contract](../documentation/standard-library/cli.md), [entry validation](../pkg/compiler/compiler.go), and [execution-local accessors](../pkg/runtime/host.go).
Verify: a parameterless entry runs; parameterized entries fail; imported accessors share roots across derived executions and imported helpers, while separate tests receive separate root wrappers.

### Keep short bodies available without a second function kind

Decision: the user requested a terse language with single-line functions and conditions. Do not restore the earlier blanket requirement for indented function bodies. The user clarified that `else` must start on a separate line: allow one branch per line, and reject same-line `else` or `else if`. Inline suites use the existing colon and explicit statement/return semantics; they do not introduce implicit returns or a separate callable kind.

Apply when: changing suite parsing, anonymous-function layout, formatting, or syntax documentation.
Evidence: [canonical suite rules](../documentation/core-language/basics/grammar.md#statements-and-patterns), [parser boundary cases](../pkg/parser/parser_test.go), and [native inline conformance](../tests/e2e/testdata/accept/inline-suites.ms).
Verify: parse an inline callback inside a call without consuming the enclosing delimiter; execute inline and indented branches together; preserve formatting idempotence and reject multiple statements in an inline body.

### Optional values need presence and extraction methods

Decision: the user explicitly rejected relying on `match` for routine Optional handling. Keep one receiver surface: `is_some`, `is_none`, `unwrap`, `unwrap_or`, and `unwrap_or_else`. Preserve Optional as an ordinary alternative; these methods do not introduce flattening or new syntax. The private native helpers are implementation bindings, not exported aliases.

Decision: the later request to accept `Queue[Int](capacity: 4)` permits a plain payload at standard Optional argument boundaries. Routine calls and current examples use plain values rather than redundant `some(...)` arguments. Keep this separate from omission permissions and ordinary assignment/return compatibility. Lower the supplied argument to a real `some` value so source implementations and native APIs receive the same representation; preserve written evaluation order and payload identity.

Apply when: changing Optional declarations, alternative method lookup, fallback evaluation, or introductory examples.
Evidence: [Optional contract](../documentation/core-language/types/optionals.md#checking-and-extracting-values), [optional argument rules](../documentation/core-language/types/optionals.md#passing-optional-arguments), [canonical declaration](../pkg/stdlib/optional.ms), [compiled method fixture](../tests/e2e/testdata/accept/optional-methods.ms), and [argument conformance](../tests/e2e/testdata/accept/optional-arguments.ms).
Verify: false and zero are present; eager defaults evaluate normally; lazy defaults run exactly once only for none; unwrap on none faults clearly. Extraction retains nested type arguments and payload identity, stored receiver methods still work, and local alternatives with the same spelling receive no native methods.

Verified: Optional argument checking retains the expression's source type and records wrapping separately, so editor queries and Boolean folding keep their existing meaning. Reuse an inferred payload type before retrying with context: checking every nested call twice causes exponential work for both accepted and rejected inputs. Evidence: [source/AST regression](../pkg/checker/optional_test.go), [nested call regression](../pkg/compiler/optional_test.go), and [argument checking](../pkg/checker/calls.go).

### Collection storage can guard different recursive element types

Verified: tracking List/Map/Set nominal identities as active generic applications rejected valid recursive trees when a path crossed two collections with different element types. Collection storage is indirect; recurse into its arguments without treating that collection's identity as a user-defined generic cycle. Continue checking active user type identities so genuinely growing generic recursion is rejected.

Apply when: changing recursive layout checking or adding recursive data types.
Evidence: [layout checker](../pkg/checker/contracts.go), [accepted and rejected layout regressions](../pkg/checker/checker_test.go), and [compiled TOML node trees](../tests/e2e/testdata/stdlib/toml.ms).
Verify: `TestNestedCollectionsGuardRecursiveLayouts` accepts the two Map element types and still rejects `Growing[List[T]]` recursion.

### Match is uniformly a value expression; indexing preserves Optional

Decision: when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form. A standalone match discards the same checked result. The user also clarified that list brackets must preserve `.at()`'s Optional result, rather than unwrap or introduce bounds faults. Generic specialization retains its existing meaning.

Apply when: changing matching, collection lookup, type application parsing, or examples migrating from other languages.
Evidence: [match values](../documentation/core-language/control-flow/pattern-matching.md#arm-values), [list lookup](../documentation/core-language/types/collections.md#lookup-and-updates), and [native expression conformance](../tests/e2e/testdata/accept/expression-conveniences.ms).
Verify: use `items[index].unwrap_or(0)` for absent indexes, keep `identity[Int]` specialization, and exercise enclosing returns, propagation, cleanup, and loop exits from match arms. An effects-only arm ending in a value-returning call needs an explicit `unit` when another arm produces Unit.
