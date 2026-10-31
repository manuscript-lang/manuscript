[Wiki](../index.md) › [Language](index.md)

# Local implementations must remain selected across module boundaries

Verified: accepting an implementation for an imported source type requires more than relaxing receiver ownership. Extensions are limited to their declaring module; views, bound methods, cleanup, and generic specialization retain that selection at runtime. A global receiver/contract lookup would silently select another module's extension. Inherited receiver bounds also need their resolved nominal identities, rather than resolving their source spelling again in the extending module. Implementation details are in [compiler.md](../compiler/index.md).

Apply when: changing implementation visibility, generic evidence, contract wrappers, cleanup dispatch, or editor member lookup.
Evidence: [coherence and visibility](../../documentation/core-language/types/contracts.md#coherence-and-visibility); [cross-module dispatch project](../../tests/e2e/testdata/projects/local_extensions/conformance_test.ms).
Verify: two modules implement the same imported pair with different results; returned views and specialized functions retain their results, while raw values do not acquire either extension in a third module. Forwarding a generic argument must not change dispatch on statically concrete receivers in the callee.
