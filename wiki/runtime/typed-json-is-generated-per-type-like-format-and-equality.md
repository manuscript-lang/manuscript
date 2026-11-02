[Wiki](../index.md) › [Runtime](index.md)

# Typed JSON is generated per type, like format and equality

Decision: the owner asked for `json.parse` and `json.stringify` themselves to work with types, with no separate `decode` and no new syntax, and for JavaScript's `JSON.stringify` behavior: every type is accepted and nothing is rejected at compile time. Two interfaces customize shapes: `JsonEncode.to_json` exists; the `JsonDecode` counterpart is undecided (a record implementing it was proposed because contracts have no static operations).

Apply when: adding a standard value type with its own text or number form (extend encoding and decoding together), changing the encoding, or adding typed YAML/TOML encoding.
Evidence: [declarations and guide](../../stdlib/data/json.ms), [JSON lowering](../../crates/ms-lower/src/json.rs), [JSON crate](../../crates/ms-std-json/src), [native conformance](../../tests/e2e/testdata/stdlib/json.ms), [typed codecs](../../tests/e2e/testdata/stdlib/typed-codecs.ms).
Verify: a record with a function field and a `none` field encodes without them; `Wrapper[Wrapper[String]]` with a defaulted field decodes; a round trip through `stringify` returns identical text.
