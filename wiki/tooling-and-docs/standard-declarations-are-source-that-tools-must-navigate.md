[Wiki](../index.md) › [Tooling and docs](index.md)

# Standard declarations are source that tools must navigate

Decision: the user asked to keep standard type definitions in Manuscript so editor tooling can use them. `stdlib/*.ms` supplies public schemas and signatures; `extern fn` and `extern type` declarations name the native symbols and types. Generated documentation and navigation consume this source-backed contract.

Verified: mixed modules keep checked source methods under `<module>+source`, which public module enumeration hides. API extraction must include those methods and preserve their receiver constraints; [discovery regressions](../../crates/ms-tooling/tests/guide_extensions.rs) cover bounded methods, overloads and repeated implementation records.

Public API snapshots also honor the checked type's opaque boundary: mark the declaration opaque and omit its fields, cases and case payloads while retaining callable methods. Source navigation can still reach the defining declaration; it does not make those structures available to callers ([regressions](../../crates/ms-tooling/tests/guide_opaque.rs)).

Apply when: adding standard APIs, changing their signatures, or extending hover/navigation/documentation.
Evidence: [declaration ownership](../../stdlib/intrinsics.ms); [standard checking](../../crates/ms-check/src/stdlib.rs); [documentation generator](../../crates/ms-tooling/src/guide/docgen.rs); [client](../../extensions/vscode/extension.js); [client tests](../../extensions/vscode/tests/extension.test.js).
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration and can follow imports and signature types from there, and source documentation and the generated book pass their checks (`make docs-check`).
