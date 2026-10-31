[Wiki](../index.md) › [Language](index.md)

# Syntax improvements need examples across their boundaries

Decision: support grouped symbol imports and brace Map literals. The user's newer explicit request to "remove mandatory labels for invoking functions" supersedes the prior restriction to single-parameter unlabeled calls. Invocation labels are optional across functions, methods, function values and constructors. Superseded by issue #452 (user direction): an unlabeled argument, including a bare identifier, is always positional and never selects a parameter by its spelling; only `name: value` selects by name.

Apply when: changing calls, grammar, inference or editor assistance.
Evidence: [canonical call rules](../../documentation/core-language/functions/declarations-and-calls.md#argument-names); [native calls](../../tests/e2e/testdata/accept/positional-arguments.ms).
Verify: positional/labeled/mixed calls bind deterministically, a bare identifier fills the next unfilled slot whatever its name, supplied values execute once in written order before defaults, and callable compatibility ignores names while rejecting parameter/result type mismatches.
