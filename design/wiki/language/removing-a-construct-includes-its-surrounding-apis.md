[Wiki](../index.md) › [Language](index.md)

# Removing a construct includes its surrounding APIs

Decision: the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests. The user wanted ordinary `if`/`return` control flow. Removing the syntax alone did not satisfy the requested surface.

Apply when: removing or renaming language constructs or standard APIs.
Evidence: none recorded.
Verify: inventory related exported helpers and aliases before editing, regenerate references, then check every surface covered by the removal request. Follow an explicit zero-reference request when deciding whether rejection tests should retain the old spelling.

Release rule (0.1.0 prep, 2026-11-15): every removed or renamed spelling gets a `tests/checks/removed/` snippet in the same change; `make removed-check` fails unless the error names the replacement. The first run found two silent removals (`@std/concurrency/flow.ms`, `String.byte_length`), now fixed in the removed-name hints of the checker.
The same snippets also pin the fix: `// fix:` names the text `ms check --only types --fix` must produce, or `none: <why>` (only `impl` blocks and host getters, whose replacement depends on the program). Adding a fix changes a fixture's recorded diagnostic (`fix` field, wider caret); re-record it with `ms run tools/conform-run.ms -- --record <fixture id>`.
