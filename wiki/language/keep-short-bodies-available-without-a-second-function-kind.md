[Wiki](../index.md) › [Language](index.md)

# Keep short bodies available without a second function kind

Decision: the user requested a terse language with single-line functions and conditions. Do not restore the earlier blanket requirement for indented function bodies. The user clarified that `else` must start on a separate line: allow one branch per line, and reject same-line `else` or `elif`. The latest correction permits a single expression after a function or method colon and implicitly returns it. Multiline bodies retain explicit returns.

Apply when: changing suite parsing, anonymous-function layout, formatting, or syntax documentation.
Evidence: [canonical suite rules](../../documentation/core-language/basics/grammar.md#statements-and-patterns), [inline suite fixture](../../tests/e2e/testdata/accept/inline-suites.ms).
Verify: parse an inline callback inside a call without consuming the enclosing delimiter; execute inline and indented branches together; preserve formatting idempotence and reject multiple statements in an inline body.
