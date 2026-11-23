[Wiki](../index.md) › [Tooling and docs](index.md)

# The language server is C in src/cli, and the Rust crate is its oracle

Verified: 2026-11-23, `src/cli/lsp_*.c`.

Chinmay chose (2026-11-23) to write `ms lsp` in C beside the other commands, not in Manuscript: nothing in the C build runs embedded Manuscript commands, and the C checker already has the occurrence index. This replaces the earlier plan to rewrite `crates/ms-lsp` as a Manuscript program.

- `crates/ms-lsp` is the behavioural oracle: copy its error codes, capabilities, position rules and message shapes, and advertise a capability only once it works.
- Each open document is checked as the entry of its own graph, with every open document's text as the overlay. Only findings in that document are shown.
- Sessions are tested with `tests/lsp/<case>/requests.jsonl` and `expected.jsonl`, replayed over standard input and output by `cmake/LspSession.cmake` (`-DRECORD=1` records). `$ROOT` and `$ROOT_URI` stand for the case directory; the version is `$VERSION`. The script is CMake so it runs the same on all three platforms.
- `file(READ)` turns CRLF into LF, so the replay finds a header's end at a blank line.
- Completion and signature help re-check the document with the word under the cursor replaced by a marker name written as a call (not in type position); the scope walk at the marker gives the locals. Function types intern without parameter names, so names and defaults come from the declaration.
- Analyses are cached per entry file and invalidated by a global generation counter that every document change and `workspace/didChangeWatchedFiles` bumps.
- Imports: module paths and exported names are completed straight from parsed bundled and project files (no checker run). Opened `manuscript-stdlib:` documents take the bundled text (the client's is ignored) and are checked as a stand-in file in the temporary directory (`ms-stdlib-<name>`); they publish no diagnostics and refuse edits, formatting, fixes and renames. A type variable's type row holds a variables index in `def`: never pass it to `ms_defs_get`.
- `ms lsp` is a supervisor around a worker copy of itself (`MS_LSP_WORKER=1`). A crash fails the unanswered requests, restarts the worker and replays `initialize` and the open documents. Input is read on its own thread (`lsp_input.c`), which is how `$/cancelRequest` is seen mid-request and how a run of `didChange` frames is published once. Never leave the process through `exit`: the reader thread holds stdin's lock inside `fread`, so `exit` deadlocks; use `lsp_input_exit`. Replay tests cannot check cancellation or restart (all input arrives before the first request is handled); verify those by hand with a driver that kills the worker.
