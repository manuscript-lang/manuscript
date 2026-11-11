[Wiki](../index.md) › [Language](index.md)

# Write terse Manuscript

Decision (Chinmay, 2026-11-09): code, examples, and docs use the shortest form the language already offers. Verbose shapes were mostly written without knowing an existing method.

Use instead of:
- `print("x")` over `stdout().write("x\n").get()`; `stdout()` only for bytes, no newline, or handled errors.
- `a.length().max(b.length())` over `var m = a.length()` plus `if ...: m = ...`. The Int methods are ambient in user code and in stdlib modules outside the extension-module import closure; `math`, `string` and `big` cannot see them (cycle), so those write `max(a, b)`.
- `[0].repeated(n)` (one element takes a native fill), `(0..n)`, `.map`, `.filter`, `.any`/`.all`, `.sum()`, `.contains` over loops that build a list or accumulate; `for _round in` over `unusedN` (bare `_` is a reserved word; names starting `_` are exempt from unread and shadowing checks); `xs.extend(ys)` over a loop that appends copies.
- `x := if c: a else: b` over `var x = a` plus a reassignment.
- `.is_empty()` over `.length() == 0`; no `== true`; no `else:` after `return`.
- `if v := x`, `get(default)`, `?` over `is_none()` guards and `match` unwrapping. Avoid chained `.get(a).get(b)`; use `get_or(key, default)` on a Map (`Headers`, `JsonValue` and `Result` lack it). Inside a type's own `get_or` do not write `self.get_or`: it recurses.
- `"""` multi-line literals over `+ "\n" +` chains.

Tests and bench sources follow the same idioms (2026-11-09, Chinmay). Rewriting a conformance fixture shifts recorded line numbers: re-record only the `-fmt` twins (`ms-conform record --ms target/release/ms --id <id>`) and revert any other fixture whose output changes. Leave `tests/ownership-counts` (allocation counts depend on the code), `bench/perf` and `bench/language` kernels (they measure the written loop), fuzz fixtures (generated), and fixtures that exercise the verbose form. `repeated` loops and clones, so keep native `filled` in hot paths.
Evidence: scan with counts in the project file terse-manuscript/catalog.md (2026-11-09).
Verify: `ms fmt --check`, `make conform`, `make repo-check`.

Rewrite hazards found: an `if` expression cannot replace `var x = a; if c: x = b` when `c` or `b` reads `x`, when `x` is reassigned later, or with `if v := x` (not an expression); `.get_or` on a type that defines its own `get_or` recurses. Do not bulk-edit `tests/e2e` fixtures that exist to exercise the verbose form.
