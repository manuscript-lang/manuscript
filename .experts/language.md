# Language lessons

### An unsaved overlay cannot replace a dangling source symlink

Verified: editor overlays may create a file beneath an existing confined directory, but a dangling symlink remains a filesystem entry whose target identity must be respected. Treating every `EvalSymlinks` not-found result as an unsaved file allowed an overlay to hide an unresolved external target. Source path resolution now rejects that fallback for existing entries.

Apply when: changing project resolution, filesystem identity, or editor overlays.
Evidence: [source path resolution](../project/paths.go), [symlink/overlay regressions](../project/project_test.go), and [strict versus recovery compilation](../compiler/metadata_test.go).
Verify: new confined overlay files compile without being written to disk; overlays for outside paths, dangling external links, or symlinked external parents are rejected. Normalize accepted overlay keys to canonical file identity so symlinked workspace directories retain unsaved content; reject conflicting snapshots of one file. Recovery keeps valid declarations while diagnostics still prevent generated executable source.

### String conversion is available on every value

Decision: the user requested JavaScript-like conversion with `toString()` on everything. This supersedes the previous restriction of interpolation to scalars. Conversion is available in unconstrained generic code and uses the same representations as interpolation; ordinary type compatibility at assignment, call, and return boundaries remains explicit.

Apply when: changing interpolation, member resolution, formatting, or editor member queries.
Evidence: [canonical conversion rules](../documentation/core-language/basics/text-and-bytes.md#converting-values-to-string); [native source conformance](../tests/e2e/testdata/accept/to-string.ms); [opaque and cyclic formatting checks](../runtime/format_test.go).
Verify: a record and an unconstrained `T` both support `.toString()` and direct interpolation; a closed resource converts without invoking an operation; passing that record directly to a String parameter is still rejected.

### Local implementations must remain selected across module boundaries

Verified: accepting an implementation for an imported source type requires more than relaxing receiver ownership. The checker limits extensions to their declaring module; views, bound methods, cleanup, and generic specialization retain that selection at runtime. A global receiver/contract lookup would silently select another module's extension. Inherited receiver bounds also need their resolved nominal identities, rather than resolving their source spelling again in the extending module.

Apply when: changing implementation visibility, generic evidence, contract wrappers, cleanup dispatch, or editor member lookup.
Evidence: [coherence and visibility](../documentation/core-language/types/contracts.md#coherence-and-visibility); [boundary and inherited-bound checks](../compiler/local_extensions_test.go); [native cross-module dispatch fixture](../tests/e2e/testdata/projects/local_extensions/main.ms); [editor visibility and navigation](../tooling/lsp/completion_test.go).
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

Verified: when rebasing standard-library work onto current main, migrate new conformance fixtures and documentation examples to ordinary `if not (...)` checks returning `panic`; do not restore the removed testing module or its native bindings from a stash. The source-level [built-in parity fixture](../tests/e2e/testdata/accept/builtin-parity.ms) exercises this form, and [standard bindings](../stdlib/bindings.json) remain free of the removed module.

### Error translation does not need a dedicated standard helper

Decision: remove the specialized Result error-mapping helper and keep the documentation focused on ordinary functions and explicit matching. The user's correction rejects extra API machinery for a transformation that existing control flow expresses. Keep `try`'s exact-error-type rule; do not replace the helper with implicit conversions.

Apply when: adding Result adapters or rewriting examples that combine execution and domain errors.
Evidence: the user's removal request; [error compatibility](../documentation/core-language/errors/propagation.md#error-compatibility); [parallel example](../documentation/concurrency/parallel.md).
Verify: examples compile with explicit Result matches, the standard Result module exports only its type, and regenerated API references agree with its declarations.

### Latest choices can supersede an apparently accepted alternative

Decision: keep `Equal` and `Hashable` derived. The later concurrency simplification removed compiler sharing bounds: all values may be passed freely, and `Synchronized[T]` guards protect shared mutable access and complete updates. The subsequent local Queue decision requires explicit synchronization for concurrent access. The user briefly requested custom equality implementations, then explicitly reversed that choice. Explicit closure capture lists were also rejected; the subsequent universal-sharing decision supplies the current sharing design.

Apply when: changing bounds, equality, capture syntax, or callable sharing.
Evidence: [equality reversal](codex://threads/01a12aed-fa8a-7d93-b522-38e95f93fdf5); [capture-list rejection](codex://threads/01a12bf3-438d-7c72-a846-7443cea58e3a); [canonical equality rules](../documentation/core-language/types/equality-and-hashing.md); [current callable sharing rules](../documentation/ownership-and-cleanup/values/sharing.md#function-values).
Verify: examples follow current equality derivation and ordinary callback rules. Rejected alternatives remain rejected unless the user deliberately reopens them; an earlier “yes” does not override a later correction.

### Syntax improvements need examples across their boundaries

Decision: support grouped symbol imports, and allow an omitted call label for a function with one parameter while requiring labels for functions with more than one parameter. The single-parameter request measures declaration arity, not the number of arguments supplied. These are user decisions; verify their availability in the branch being changed.

Apply when: changing imports, calls, grammar, or editor assistance.
Evidence: [grouped-import request](codex://threads/01a12e1a-7d2d-7646-b5fc-2dc8fdd60038); [single-parameter request](codex://threads/01a12e4a-98e8-775e-9e6c-c101a8ac300d).
Verify: grouped imports resolve each symbol and its editor location; one-parameter calls exercise both spellings, multi-parameter calls require labels, and missing arguments still fail. Consult current grammar and compatibility rules for methods, constructors, and function values rather than assuming identical boundaries.

### Recover concrete contract receivers through checked matching

Decision: a common Error contract must allow both generic diagnostics and specific handling without discarding the concrete cause. Apply the ordinary operation-contract rules: explicit implementations and views, invariant Result types, and explicit error mapping. Contract matches use concrete record/alternative type patterns with exactly one receiver binding and a final wildcard for other implementations.

Apply when: changing Error boundaries, contract views, matching, or native standard implementations.
Evidence: [contract type patterns](../documentation/core-language/control-flow/pattern-matching.md#contract-type-patterns); [common error boundary](../documentation/core-language/errors/results.md#a-common-error-boundary); [compiled errors and generic patterns](../tests/e2e/testdata/accept/library-errors.ms); [invalid contract patterns](../compiler/library_test.go).
Verify: exact nominal identities and generic arguments determine a match; the receiver and payload survive conversion and propagation; missing implementations, incomplete generic patterns, and missing fallbacks are rejected.

### Default arguments must not leak across callable replacement

Verified: defaults are permissions on a known callable, not part of function-type identity. Retaining that permission on a mutable binding or inferred generic type could let a required-argument function replace a defaulted function, then be called with a missing argument. Explicit function types, mutable bindings, and generic inference erase defaults; inferred immutable copies retain them.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../documentation/core-language/functions/declarations-and-calls.md#default-arguments); [boundary rejection tests](../checker/defaults_test.go); [native default behavior](../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.

### Mutable data uses explicit shallow cloning

Decision: ordinary record fields and collections are mutable. The user rejected immutable replacement APIs and instance freezing in favor of `.clone()`. Preserve `let`/`var` binding rules independently of object mutation. Clone data storage shallowly; do not manufacture copies of sockets, files, locks, or other native service handles. A cloned record may retain the same handle reference.

Apply when: changing fields, collection updates, aliases, copies, equality, or concurrency guidance.
Evidence: [record contract](../documentation/core-language/types/records.md#mutation-and-cloning); [collection contract](../documentation/core-language/types/collections.md#mutation-and-copies); [native conformance](../tests/e2e/testdata/accept/mutation.ms); [resource clone rejection](../compiler/mutation_test.go); [CLI rejection and shared file lifetime](../tests/e2e/mutation_test.go).
Verify: the counter's Unit-returning method updates `self.val`; aliases observe mutation; a clone's outer storage stays separate while its nested references remain shared. Native resource clone calls are rejected. Protect concurrent mutation with existing Synchronized guards; do not restore removed sharing bounds.

### Parameterless main and imported host accessors

Decision: applications export `fn main() -> Int` and import the standard services they use. The user explicitly deferred enforcement; the earlier exploration of `using`, scoped replacement, and manifest permissions is not an accepted implementation requirement. Ordinary service parameters remain available for helpers and source fakes.

Apply when: changing entrypoints, host roots, standard imports, tests, or authority documentation.
Evidence: [CLI host contract](../documentation/standard-library/hosts/cli.md), [entry validation](../compiler/compiler.go), and [execution-local accessors](../runtime/host.go).
Verify: a parameterless entry runs; parameterized entries fail; imported accessors share roots across derived executions and imported helpers, while separate tests receive separate root wrappers.
