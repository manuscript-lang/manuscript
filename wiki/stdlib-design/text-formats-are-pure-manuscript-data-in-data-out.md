[Wiki](../index.md) › [Standard-library design](index.md)

# Text formats and templates are pure Manuscript over JsonValue

Decision (2026-11-02): templates (`@std/text/template.ms`), XML, PEM, MIME/multipart and mail parsing are written in `.ms` with no Rust parser and no new crate (PR #2258 was closed for adding `leon`/`miette` and a Rust parser). Templates read `JsonValue` data (`to_data` converts any `Data` value) and cannot call functions; there is no reflection. Capability matters, not Go's API: no `text/scanner` (belongs with the bufio-style `Scanner`), no gob.

Verified: `String.split(sep, n)` truncates to the first `n` pieces rather than keeping a remainder, `List.get(i, default)` takes a default, a `{`/`}` inside a string literal must be written `\{`/`\}`, `test` is a keyword and cannot name a binding, and an exported record may not expose a private type (an opaque `Template` needs exported opaque node types with documented fields).

Apply when: adding a text format, parser or template feature.
Evidence: [template.ms](../../stdlib/text/template.ms), [xml.ms](../../stdlib/data/xml.ms), [mime.ms](../../stdlib/net/mime.ms), fixtures in `tests/e2e/testdata/stdlib/`.
Verify: `ms test tests/e2e/testdata/stdlib/template.ms` and `make docs-check`.
