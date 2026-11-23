[Wiki](../index.md) › [Tooling and docs](index.md)

# The language server is C in src/cli, and the Rust crate is its oracle

Verified: 2026-11-23, `src/cli/lsp_*.c`.

Chinmay chose (2026-11-23) to write `ms lsp` in C beside the other commands, not in Manuscript: nothing in the C build runs embedded Manuscript commands, and the C checker already has the occurrence index. This replaces the earlier plan to rewrite `crates/ms-lsp` as a Manuscript program.

- `crates/ms-lsp` is the behavioural oracle: copy its error codes, capabilities, position rules and message shapes, and advertise a capability only once it works.
- Each open document is checked as the entry of its own graph, with every open document's text as the overlay. Only findings in that document are shown.
- Sessions are tested with `tests/lsp/<case>/requests.jsonl` and `expected.jsonl`, replayed over standard input and output by `cmake/LspSession.cmake` (`-DRECORD=1` records). `$ROOT` and `$ROOT_URI` stand for the case directory; the version is `$VERSION`. The script is CMake so it runs the same on all three platforms.
- `file(READ)` turns CRLF into LF, so the replay finds a header's end at a blank line.
