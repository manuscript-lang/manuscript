[Wiki](../index.md) › [Tooling and docs](index.md)

# The language server is being rewritten in Manuscript

Verified: 2026-11-20, tools/lsp.

Chinmay chose to rewrite `ms-lsp` as a Manuscript program (`src/lsp/`) and then delete the crate. The Rust server is the behavioural oracle: copy its error codes, capabilities and position rules, and port a feature only with the Rust behaviour in mind.

- Done: framing, JSON-RPC errors, initialize/shutdown order, incremental sync with UTF-16 positions, diagnostics, formatting (`ms fmt` on the scratch copy), folding and the outline (`structure.ms`, read from indentation so they work while the source has errors; the outline has no checked-type detail yet).
- Diagnostics and formatting run `ms check --json` and `ms fmt` on the buffer written beside the file under a hidden name (`scratch.ms`) (`$MS_RUST_CLI`, default `ms-rust`). Only that file's own issues are shown, and other open buffers are not overlaid. Replace this with facts from the C checker; remove the temp-file step then.
- Edits batch: diagnostics for changed documents go out once per burst of input, and before any request, `shutdown` or `exit`.
- Next: hover, definition, completion, then the rest of the Rust feature list. Advertise a capability only once it works.
- `make lsp-test` runs the unit tests. Position and framing helpers are pure so tests need no editor.
