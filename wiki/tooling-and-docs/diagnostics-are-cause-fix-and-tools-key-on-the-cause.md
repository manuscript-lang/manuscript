[Wiki](../index.md) › [Tooling and docs](index.md)

# Diagnostics are `<cause>; <fix>`, and tools key on the cause

Verified: agents act on a diagnostic only when it names the cause, the location, and a concrete fix (nearest name, import line, valid options). Messages therefore read `<cause>; <fix>`. A diagnostic's rule code classifies only the text before the first `; `, so fix text cannot change a rule code. Partial parsing recovers from an unterminated delimiter by matching the message prefix, and the lexer reports it at end of file; moving that position or exact wording breaks editor recovery.

Apply when: adding or rewording any lexer, parser, checker, project, compiler, CLI, or runtime message.
Evidence: [message-shape rule](../../documentation/developer-tooling/source/diagnostics.md), [code classification](../../crates/ms-syntax/src/diag.rs), [checker hints](../../crates/ms-check/src/hints.rs), [recovery](../../crates/ms-syntax/src/partial.rs).
Verify: run `cargo nextest run -p ms-syntax -p ms-check -p ms-lsp -p ms-cli` and `make conform` (check-phase fixtures compare code, phase, message, and position); extend the hint tests with the new message.
