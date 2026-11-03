[Wiki](../index.md) › [Compiler and build](index.md)

# Native omissions are declared in the standard declaration

Verified: defaults for native functions, methods, and constructor fields are written in the standard `.ms` declaration and checked as ordinary expressions. Constructor omission follows source metadata, application implementations inherit standard interface default permissions and receive concrete values, and native compositions pass `some(n)` through source-defined streams.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [native default checking](../../crates/ms-check/src/native_defaults.rs), [native defaults fixture](../../tests/e2e/testdata/stdlib/defaults.ms), [stdlib revamp fixture](../../tests/conformance/fixtures/e2e/accept/stdlib-revamp.ms).
Verify: exercise stored, bound, and generic calls that omit a defaulted argument and fresh records; omit a limit through an application-defined ReadStream and match `none`.

## Native receiver operations are derived from the declaration

Verified: a bodiless inherent method of a standard type is a native receiver operation, found by the loader (`is_receiver_native` in `ms-check/src/stdlib.rs`); there is no table of bindings. Its native identity is the method name, so lowering tells receivers apart by type: a `native == "chars"` test also needs `str_recv`, and `abs`, `sign` and `compare` check `is_int` or `is_float`. `// ms: keeps` and `// ms: owns` on a runtime function replace name lists for kept callbacks and owned values (`@keeps`, `@owns` in `rt_symbols.txt`).
Apply when: adding a native method or a receiver-specific lowering arm; a name-only match collides with other receivers.
Verify: `make conform`; `runtime_flags_come_from_the_symbol_table`.
