[Wiki](../index.md) › [Language](index.md)

# Removing a construct includes its surrounding APIs

Decision: the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests. The user wanted ordinary `if`/`return` control flow. Removing the syntax alone did not satisfy the requested surface.

Apply when: removing or renaming language constructs or standard APIs.
Evidence: none recorded.
Verify: inventory related exported helpers and aliases before editing, regenerate references, then check every surface covered by the removal request. Follow an explicit zero-reference request when deciding whether rejection tests should retain the old spelling.
