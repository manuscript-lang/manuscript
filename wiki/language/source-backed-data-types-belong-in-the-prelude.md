[Wiki](../index.md) › [Language](index.md)

# Source-backed data types belong in the prelude

Decision: the user requested Optional, Result, their related helpers, and Error without imports. The later accepted [issue #187 direction](https://github.com/manuscript-lang/manuscript/issues/187#issuecomment-6138072921) adds List and Map to that scope; Set uses the same mechanism. The latest direction removes existing imports and requires every type referenced by the public List/Map/Set API in the prelude.

Apply when: changing prelude scope, standard imports, case lookup, or editor auto-imports.
Evidence: [module scope rules](../../documentation/core-language/modules/declarations.md#names-and-declaration-order), [prelude conformance](../../tests/e2e/testdata/accept/prelude.ms), [collection execution](../../tests/e2e/testdata/accept/collection-prelude.ms), [Set execution](../../tests/conformance/fixtures/e2e/accept/set-prelude.ms), [prelude import resolution](../../crates/ms-check/src/prelude_imports.rs).
Verify: Optional methods and Result propagation into Error execute without imports; incomplete constructors and ambiguous cases still fail; editor completion adds no redundant import and definitions reach standard source.
