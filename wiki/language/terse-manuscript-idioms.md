[Wiki](../index.md) › [Language](index.md)

# Write terse Manuscript

Decision (Chinmay, 2026-11-09): code, examples, and docs use the shortest form the language already offers. Verbose shapes were mostly written without knowing an existing method.

Use instead of:
- `print("x")` over `stdout().write("x\n").get()`; `stdout()` only for bytes, no newline, or handled errors.
- `a.length().max(b.length())` over `var m = a.length()` plus `if ...: m = ...` (Int `max`/`min`/`clamp` methods are not implemented yet; today `max` is a free function in `@std/math`).
- `[0].repeated(n)`, `(0..n)`, `.map`, `.filter`, `.any`/`.all`, `.sum()`, `.contains` over loops that build a list or accumulate; `for _ in` over `unusedN`.
- `let x = if c: a else: b` over `var x = a` plus a reassignment.
- `.is_empty()` over `.length() == 0`; no `== true`; no `else:` after `return`.
- `if let`, `get(default)`, `try` over `is_none()` guards and `match` unwrapping. Avoid chained `.get(a).get(b)`; use `get_or` on maps.
- `"""` multi-line literals over `+ "\n" +` chains.

Do not rewrite `tests/conformance` fixtures for style: their expected output holds line numbers, so edits fail the corpus. Keep fixtures that exist to exercise the verbose form. `repeated` loops and clones, so keep native `filled` in hot paths.
Evidence: scan with counts in the project file terse-manuscript/catalog.md (2026-11-09).
Verify: `ms fmt --check`, `make conform`, `make e2e`, `make repo-check`.
