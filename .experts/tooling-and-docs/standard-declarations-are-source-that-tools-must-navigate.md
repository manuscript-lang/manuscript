[Wiki](../index.md) › [Tooling and docs](index.md)

# Standard declarations are source that tools must navigate

Decision: the user asked to keep standard type definitions in Manuscript so editor tooling can use them. `stdlib/*.ms` supplies public schemas and signatures; `extern fn` and `extern type` declarations name the native symbols and types. Generated documentation and navigation consume this source-backed contract.

Verified: bundled modules containing bodies use ordinary Manuscript parsing and checking. Publish only module-owned exports: a checked module's name table also contains imported symbols and prelude types, which must not become new exports. Native declarations retain empty bodies and ABI bindings; all standard modules use ordinary parsing. The user requires ordinary empty functions with colon headers, including receiver functions, and empty opaque schemas with colons. Do not replace these with a `native` modifier, and do not hide invalid syntax in a permissive library-only parser (that once concealed missing bodies, mixed receiver signatures, and field-default errors). `make repo-check` validates working-tree stdlib sources and returns a positioned error before checker initialization.

Verified: navigation must continue after the first jump into a standard declaration. Register the virtual document scheme with the language client and keep the resolved type references for tooling; reparsing library signatures as executable workspace modules loses their checked context. Keep virtual documents immutable and outside workspace source overlays.

Apply when: adding standard APIs, changing their signatures, or extending hover/navigation/documentation.
Evidence: [declaration ownership](../../stdlib/intrinsics.ms); [standard checking](../../crates/ms-check/src/stdlib.rs); [documentation generator](../../crates/ms-tooling/src/guide/docgen.rs); [client](../../extensions/vscode/extension.js); [client tests](../../extensions/vscode/tests/extension.test.js).
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration and can follow imports and signature types from there, and source documentation and the generated book pass their checks (`make docs-check`). Regenerate from combined source after integration: adding List/Map to the prelude makes their receiver additions appear in the prelude reference as well as the collections reference, and a conflict-free merge can still leave generated artifacts stale. Member-description extraction changes also require combined regeneration, even when merged signature strings remain current.

Decision: the string utility module is `@std/string.ms`, matching the intrinsic `String` type. The user requested this spelling when expanding built-in parity. Receiver operations need no module import; standalone string functions use this canonical module. Evidence: [declarations](../../stdlib/string.ms), and [data package guide](../../stdlib/collections.ms). When renaming a module, verify imports, native dispatch identities, virtual editor documents, and generated reference paths together.

---
Topics: [Standard-library API shape](../topics/stdlib-api-shape.md) · [Documentation](../topics/documentation.md)
