[Wiki](../index.md) › [Tooling and docs](index.md)

# Recovered navigation needs local header ranges

Verified: a malformed neighbor can prevent whole-document lexing while recovery still checks later declarations. Falling back to the declaration keyword then indexes the wrong bytes as its name: hover misses the name and outline selection is empty. Share a declaration-line fallback between occurrence indexing and document symbols, using checked names and original offsets.

Apply when: changing recovered editor navigation or declaration selection ranges.
Evidence: [header lookup](../../crates/ms-lsp/src/lexical.rs); [navigation and outline regressions](../../crates/ms-lsp/tests/recovery_navigation.rs).
Verify: declarations following an unmatched opener, rejected character, or unterminated string retain exact name ranges with LF/CRLF.
