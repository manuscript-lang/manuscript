# Occurrence index in the C tooling layer

## Summary

- Problem: two commands of the C driver are short of the Rust ones because the C checker has no occurrence index (every resolved declaration and use, keyed by identity). `ms diagram --format html` ships an empty type-hint table, and `ms search_symbol` finds standard-library symbols only. The Rust index is `crates/ms-lsp/src/index.rs` (1.5k lines) with `nav.rs` and `query.rs`.
- Change: `src/tooling/occurrence.c` builds the index of the user modules from the checker's facts (types per node, refs per node, call and local tables). Entries carry module, byte range, identity key, declaration and write flags, and type. `html` uses it for the hints; `search_symbol` uses it for declarations (workspace scan), hover text and references.
- Not changed: the facts, the checker, the Rust crates, the HTML page, and the identity key spelling (`symbol:<file>:<offset>`, `field:`, `case:`, `method:`, `operation:`, `parameter:`, `binding:`), so entries sort and group as the Rust index does.

## Status

Implemented in stages on this branch, 2026-11-22. Direction (coordinator, relaying Chinmay): gaps are not acceptable, every command at parity; reuse a Manuscript index if one exists, otherwise build it. No Manuscript language-server port or index exists in this checkout (`src/ms` is empty, no `.ms` file implements one), so the index is C in the tooling layer, small and data-oriented.

## Problem

`ms diagram --format html` on `tests/conformance/commands/diagram/html` gives `"t":[[],[]]`; the recorded Rust page carries 15 types and 70 hint rows. `ms search_symbol Shape` in a project prints no project match.

## Design

One pass per user module over the syntax tree with the module's facts:

1. Declarations: each module symbol (at its header name), type fields, enum cases, interface operations, methods, imports, parameters, and every binding site (patterns, loop and arm variables, lambda parameters).
2. Uses: names and members with a ref, constructor calls and labels, match arms, assignments.
3. Written type references and type parameters.

Entries are sorted by (file, offset, key) and de-duplicated on (file, offset, key), as the Rust index does. The hint table keeps the entries whose type resolves, and a constant shows its value type.

## Alternatives considered

- Do nothing: leaves two commands short of parity, which the owner has ruled out.
- Index the lowering instead of the syntax: lowering has no source positions for names.
- Write it in Manuscript: the C driver cannot run `.ms` tooling yet (`src/ms` is empty), so this waits for that layer; the module is small and its data is flat arrays, so porting later is mechanical.

## Testing

Differential: `ms diagram --format html` against the frozen Rust binary over the conformance projects, comparing the hint table; the recorded `diagram/html` fixture; `ms search_symbol` over projects against the same binary.
