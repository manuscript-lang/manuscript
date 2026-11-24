[Wiki](../index.md) › [Language](index.md)

# `for` and lambda parameters destructure by parser desugar

Decision (Chinmay, 2026-11-10): `for [a, b] in pairs:`, `for {name} in rows:` and `fn [a, b]: ...` accept the same list and record patterns as `:=`. The parser rewrites them to a hidden name (`for item`, `for item N`) followed by a synthetic `pattern := hidden` as the first body statement, so the checker, ownership passes and lowering needed no change and the loop variable borrows the element like any other.

Traps: the synthetic statements share the pattern's position; `Stmt::is_destructure_head` and `Lambda::written_body` identify them, and the formatter (which scans tokens, so it would run off the end looking for `=`) and its block-lambda test must skip them. A new pass that counts lambda statements or reads statement tokens needs the same. Diagnostics inside the pattern name the pattern, but a failed lambda inference names `item N`.

Apply when: changing `for` or lambda parameter syntax, or a pass that inspects statement positions.
Verify: `tests/conformance/fixtures/e2e/accept/for-destructuring.ms`, `reject/for-destructuring.ms`, and `ms fmt` leaving `fn [a, b]: a - b` inline.
