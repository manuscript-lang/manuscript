[Wiki](../index.md) › [Runtime](index.md)

# Typed JSON is generated per type, like format and equality

Decision: the owner asked for `json.parse` and `json.stringify` themselves to work with types, with no separate `decode` and no new syntax, and for JavaScript's `JSON.stringify` behavior: every type is accepted and nothing is rejected at compile time. Two interfaces customize shapes: `JsonEncode.to_json` exists; the `JsonDecode` counterpart is undecided (a record implementing it was proposed because contracts have no static operations). Lowering generates encoder and decoder helpers per concrete type (the `format` pattern) rather than walking a dynamic value model.

Verified: `try` gives its operand no backward context, so write `try parse[T](text)`. A record decode builds the value through the default-argument path, so field defaults run in the record's module with earlier fields in scope; an absent `Optional` field without a default is `none`. Map keys are parsed per key type, and two members that read as one key (`"1"`, `"01"`) are `InvalidData`. Cycle detection tracks only types that can reach themselves. Interface values have no JSON form: a view's concrete type is unknown to the encoder, and giving every view an encoder would pull JSON into every program that uses a contract.

Apply when: adding a standard value type with its own text or number form (extend encoding and decoding together), changing the encoding, or adding typed YAML/TOML encoding.
Evidence: [declarations and guide](../../stdlib/json.ms), [JSON lowering](../../crates/ms-lower/src/json.rs), [JSON crate](../../crates/ms-std-json/src), [native conformance](../../tests/e2e/testdata/stdlib/json.ms), [typed codecs](../../tests/e2e/testdata/stdlib/typed-codecs.ms).
Verify: a record with a function field and a `none` field encodes without them; `Wrapper[Wrapper[String]]` with a defaulted field decodes; a round trip through `stringify` returns identical text.

---
Topics: [Types and interfaces](../topics/types-and-interfaces.md)
