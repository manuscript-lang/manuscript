# ms.toml is TOML 1.0, and manifest values take the shape they mean

## Summary

- Problem: `ms.toml` is read by a line reader that accepts only `key = "string"`, so a list is written as one space-separated string and a dependency as `url#tag`.
- Change: read `ms.toml` with a TOML 1.0 parser, and let each key take the shape that fits: effects are arrays, a dependency may be a table.
- Decided by Chinmay: the parser is `toml_edit`; a dependency is a table `{ url = "...", tag = "v1" }` or `{ url = "...", sha = "<40 hex>" }`.

## Status

Built, 2026-11-15. Direction from Chinmay: accept the whole TOML spec, not only strings; the representation follows the need. Parser: Chinmay chose "use the toml crate"; the crate is `toml_edit`, which reads positions (needed for diagnostics) and, without the `serde` feature, brings no serde. It is the `toml_edit` crate (`parse` and `display` features; four more crates: `toml_parser`, `toml_datetime`, `toml_writer`, `winnow`), not an in-tree parser.

## Problem

`crates/ms-driver/src/project/manifest.rs` scans line by line: it splits on `=`, requires a double-quoted value, and knows five tables. Consequences: effects are a list written as a string (fixed for effects by a special case), a multi-line value or an inline table is an error, a comment after a value works only because `manifest_line` strips `#` outside quotes, and every new key needs another special case.

## Design

1. `toml_edit` (TOML 1.1 spec) in `ms-driver` produces a value tree (string, integer, float, bool, datetime, array, table) with the position of every key and value, which the manifest reader and its diagnostics already use. Everything the spec allows parses: dotted keys, `[a.b]` headers, inline tables, multi-line and literal strings, arrays of tables, comments.
2. The manifest reader walks that tree. It keeps today's tables (`project`, `aliases`, `embed`, `dependencies`, `effects`) and rejects unknown ones, so a typo still errors. Each key declares its type; a wrong type says what shape is expected and where.
3. Shapes, chosen by need:
   - `effects`: an array of strings (done).
   - `[dependencies]`: `"@pg" = { url = "<url>", tag = "v1" }` or `{ url = "<url>", sha = "<40 hex>" }` names the two parts instead of joining them with `#`; the lock keeps the joined form internally. Decided (Chinmay: each value takes the most appropriate TOML form): the table only, no string form. The string joined two fields with a separator and could not grow; the lock file keeps one line per package.
   - `[effects]`: unchanged, `"@pg" = ["std.net.*"]`.
4. Limits stay: file size, line length (64 KiB), nesting depth, no duplicate keys, no control characters in strings.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver/Cargo.toml` | `toml_edit` with `parse`, `display` | licenses inventory |
| `crates/ms-driver/src/project/manifest.rs` | read the tree instead of lines | existing manifest tests unchanged in outcome |
| `documentation/developer-tooling/builds/project-configuration.md` | say ms.toml is TOML 1.0 | doc check |

## Test cases (apply to either parser)

- Valid: bare, quoted and dotted keys; basic, literal, multi-line basic and multi-line literal strings with escapes (`é`, `\"`); integers (`1_000`, `0x1f`, `-0`); floats; booleans; offset, local date and time values; arrays that span lines with comments and a trailing comma; nested arrays; inline tables; `[a.b]` and `[[a]]` headers; CRLF line endings; a BOM; a comment on every kind of line.
- Invalid, each with a line and column: duplicate key; redefining a table; a key after an inline table closes; a bare value; an unterminated string or array; a control character in a string; `01`; a trailing `.` in a float; a mixed `[` ... `]]`; a table header after a dotted key defined it.
- Manifest level: an unknown table or key; a string where a list is expected (`effects = "x"` says "effects are a list of strings"); an array where a string is expected; `[dependencies]` with a branch name; a dependency table without `git`.
- Compatibility: every `ms.toml` in this repository (examples, tests, conformance fixtures) reads to the same project as before.
- Byte escapes: TOML strings are Unicode, so `\377` and a surrogate escape are errors, and `\xe9` means U+00E9. Non-UTF-8 file names cannot be written in `ms.toml` (the old reader could).

## Alternatives

- Do nothing: each new shape needs another special case, and `ms.toml` is not TOML in practice, which surprises everyone who writes one.
- An in-tree parser or linking the Manuscript parser in: no new crates, but a second parser to maintain, or a build step that compiles Manuscript into `ms`; Chinmay chose the crate.
- Extend the line reader a piece at a time: arrays are done; inline tables and multi-line strings are next, and it never ends at the spec.
- Call `@std/data/toml.ms` from the driver: the manifest is read before the compiler can run Manuscript.

## Stages

1. Parser and its tests, behind the existing manifest reader (no behavior change).
2. The manifest reader on the tree; dependency table form if approved.
3. Docs, wiki, ms-pg and the sample use the final shape.

## Open questions

- None.
