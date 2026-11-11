[Wiki](../index.md) › [Language](index.md)

# Standard and user code share one method syntax

Decision: the user required that the standard library, as the reference, use only forms user code can write. Methods are receiver methods, `fn Type.name(...)` and `fn var Type.name(...)`, written beside the type and never in a `type` body; an interface is satisfied by the methods alone. The `impl` keyword was removed (Chinmay, 2026-11-11: "nothing stays impl"); it parses to an error naming the receiver form. Rejected earlier: `impl Type as/with/satisfies Interface`, a comma form, and a stdlib-only `native impl`.

Apply when: changing receiver-method parsing, method declaration rules, stdlib receiver operations, or docs that show type declarations with methods.
Evidence: [contract rules](../../documentation/core-language/types/contracts.md#methods), [parser](../../crates/ms-syntax/src/parser.rs), [inherent method fixture](../../tests/conformance/fixtures/e2e/accept/inherent-methods.ms).
Verify: `def` in a `type` body is a parse error; `fn Type.name` works for exported types from the declaring module only; a receiver on another module's type and `impl` give targeted errors; `make conform` still binds every receiver operation.
