[Wiki](../index.md) › [Language](index.md)

# Standard and user code share one method syntax

Decision: the user required that the standard library, as the reference, use only forms user code can write. Methods live in `impl` blocks, never in `type` bodies: `impl Type:` declares a type's own methods and `impl Interface for Type:` implements an interface; the presence of `for` fixes which name is the type, so no lookup is needed. Rejected spellings: `impl Type as/with/satisfies Interface`, a comma form, and a stdlib-only `native impl`.

Apply when: changing impl parsing, method declaration rules, stdlib receiver operations, or docs that show type declarations with methods.
Evidence: [contract rules](../../documentation/core-language/types/contracts.md#explicit-implementations), [parser](../../crates/ms-syntax/src/parser.rs), [inherent method fixture](../../tests/conformance/fixtures/e2e/accept/inherent-methods.ms).
Verify: `def` in a `type` body is a parse error; `impl Type:` works across modules for exported types; `impl Interface:`, `impl Foreign:`, and generic methods give targeted errors; `make conform` still binds every receiver operation.
