[Wiki](../index.md) › [Runtime](index.md)

# Typed JSON is generated per type, like format and equality

Decision: the owner asked for `json.parse` and `json.stringify` themselves to work with types, with no separate `decode` and no new syntax, and for JavaScript's `JSON.stringify` behavior: every type is accepted and nothing is rejected at compile time. Two interfaces customize shapes: `JsonEncode.to_json` exists; the `JsonDecode` counterpart is undecided (a record implementing it was proposed because contracts have no static operations).

Apply when: adding a standard value type with its own text or number form (extend encoding and decoding together), changing the encoding, or adding typed YAML/TOML encoding.
Evidence: [declarations and guide](../../../src/stdlib/data/json.ms), JSON lowering, JSON crate, [native conformance](../../../tests/lang/stdlib/json.ms), [typed codecs](../../../tests/lang/stdlib/typed-codecs.ms).
Verify: a record with a function field and a `none` field encodes without them; `Wrapper[Wrapper[String]]` with a defaulted field decodes; a round trip through `stringify` returns identical text.

- A standard type whose code is Manuscript names its text functions in the lowering's source-text table (`src/compiler/lower/`: module, type, decode and encode function), not a native symbol; lowering calls the stdlib function and tests its `Result`. Only `Url` is moved so far; `Timestamp`, `Decimal`, `IpAddress` and `Cidr` still use runtime symbols until their own code moves, then switch by adding a row. Owner decision 2026-11-15: no directive, interface, `to_json` change or syntax for this; user types nested in records stay structural. The `text_forms_resolve` test fails when a named function is renamed or changes signature.

A type's own `to_json` encodes it only when it has the full `JsonEncode` shape (`fn to_json() JsonValue`, no parameters). A method named `to_json` with another signature is ordinary: matching on the name alone made `fn Repo.to_json() String!: stringify(self)` recurse until stack overflow. Interfaces match by shape, never by method name (owner decision, 2026-11-17).
