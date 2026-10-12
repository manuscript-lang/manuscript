# Language lessons

### Local implementations must remain selected across module boundaries

Verified: accepting an implementation for an imported source type requires more than relaxing receiver ownership. The checker limits extensions to their declaring module; views, bound methods, cleanup, and generic specialization retain that selection at runtime. A global receiver/contract lookup would silently select another module's extension. Inherited receiver bounds also need their resolved nominal identities, rather than resolving their source spelling again in the extending module.

Apply when: changing implementation visibility, generic evidence, contract wrappers, cleanup dispatch, or editor member lookup.
Evidence: [coherence and visibility](../design/core-language/types/contracts.md#coherence-and-visibility); [boundary and inherited-bound checks](../compiler/local_extensions_test.go); [native cross-module dispatch fixture](../tests/e2e/testdata/projects/local_extensions/main.ms); [editor visibility and navigation](../tooling/lsp/completion_test.go).
Verify: two modules implement the same imported pair with different results; returned views and specialized functions retain their results, while raw values do not acquire either extension in a third module. Forwarding a generic argument must not change dispatch on statically concrete receivers in the callee.

### Read the current decision before restoring an older design

Decision: the language rebuild was directed to use the new design on `main`. Earlier designs and assistant proposals can conflict with subsequent user corrections. Establish the target contract from the latest direction and canonical pages before borrowing old implementation ideas.

Apply when: rebuilding a feature, reusing historical code, or reconciling branches.
Evidence: [user correction in Build out the language](codex://threads/01a12c08-60dd-731b-a496-4a932d9b6000); [design index](../design/_index.md).
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
Evidence: the user's removal request; [error compatibility](../design/core-language/errors/propagation.md#error-compatibility); [parallel example](../design/concurrency/parallel.md).
Verify: examples compile with explicit Result matches, the standard Result module exports only its type, and regenerated API references agree with its declarations.

### Latest choices can supersede an apparently accepted alternative

Decision: keep `Equal` and `Hashable` derived. The later concurrency simplification removed compiler sharing bounds: all values may be passed freely, and `Synchronized[T]` guards protect shared mutable access and complete updates. The subsequent local Queue decision requires explicit synchronization for concurrent access. The user briefly requested custom equality implementations, then explicitly reversed that choice. Explicit closure capture lists were also rejected; the subsequent universal-sharing decision supplies the current sharing design.

Apply when: changing bounds, equality, capture syntax, or callable sharing.
Evidence: [equality reversal](codex://threads/01a12aed-fa8a-7d93-b522-38e95f93fdf5); [capture-list rejection](codex://threads/01a12bf3-438d-7c72-a846-7443cea58e3a); [canonical equality rules](../design/core-language/types/equality-and-hashing.md); [current callable sharing rules](../design/ownership-and-cleanup/values/sharing.md#function-values).
Verify: examples follow current equality derivation and ordinary callback rules. Rejected alternatives remain rejected unless the user deliberately reopens them; an earlier “yes” does not override a later correction.

### Syntax improvements need examples across their boundaries

Decision: support grouped symbol imports, and allow an omitted call label for a function with one parameter while requiring labels for functions with more than one parameter. The single-parameter request measures declaration arity, not the number of arguments supplied. These are user decisions; verify their availability in the branch being changed.

Apply when: changing imports, calls, grammar, or editor assistance.
Evidence: [grouped-import request](codex://threads/01a12e1a-7d2d-7646-b5fc-2dc8fdd60038); [single-parameter request](codex://threads/01a12e4a-98e8-775e-9e6c-c101a8ac300d).
Verify: grouped imports resolve each symbol and its editor location; one-parameter calls exercise both spellings, multi-parameter calls require labels, and missing arguments still fail. Consult current grammar and compatibility rules for methods, constructors, and function values rather than assuming identical boundaries.

### Default arguments must not leak across callable replacement

Verified: defaults are permissions on a known callable, not part of function-type identity. Retaining that permission on a mutable binding or inferred generic type could let a required-argument function replace a defaulted function, then be called with a missing argument. Explicit function types, mutable bindings, and generic inference erase defaults; inferred immutable copies retain them.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../design/core-language/functions/declarations-and-calls.md#default-arguments); [boundary rejection tests](../checker/defaults_test.go); [native default behavior](../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.
