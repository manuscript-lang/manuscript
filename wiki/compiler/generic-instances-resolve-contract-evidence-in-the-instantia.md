[Wiki](../index.md) › [Compiler and build](index.md)

# Generic instances resolve contract evidence in the instantiating module

Verified (carried from the retired implementation; the semantics are language rules): a module-local `impl` is visible only in its module, but a generic function from another module is instantiated with the caller's evidence for its bounded type variables, while operations on concrete types inside the body keep the declaring module's choice. A `Map` or `Set` keeps the equality and hashing it was created with, so a bound operation from another module does not change how the collection matches.

Apply when: changing implementation lookup, views, `match` on contract values, key or equality generation, or any call-site cache.
Evidence: [core parity project](../../tests/e2e/testdata/projects/core_parity/conformance_test.ms), [local extensions project](../../tests/e2e/testdata/projects/local_extensions/conformance_test.ms), [collection creator equality](../../tests/e2e/testdata/projects/preferred_names/conformance_test.ms), [contract rules](../../documentation/core-language/types/contracts.md#coherence-and-visibility).
Verify: run those three projects through `ms test`; alternate same-type views from two local-implementation modules at one nongeneric interface call site must each keep their own result.
