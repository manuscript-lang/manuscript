[Wiki](../index.md) › [Language](index.md)

# Surface syntax is its own, not Python's

Decision (user, 2026-10-28): agents slip into Python when the surface looks like Python (the Haiku bench logged 20 capitalized `True`/`False` errors), so the surface now differs on purpose. `fn f(a: Int) Int:` (no `def`, no `->`); closures `fn x: x + 1`, `fn a, b: a + b`, `fn: 1`, typed `fn(x: Int) Int: ...`; function types `fn(Int) Int` (types only, names are not identity); `true`/`false`; `unit` for the Unit value (`()` is rejected); `else if` (no `elif`); `if c: a else: b` as the expression (no `a if c else b`); plain strings interpolate with `{expr}` and escape braces as `\{` `\}` (no `f""`); `import A, B from "p"` and `import A from "p"`; match arms without `case` (`P(a):`, `_:`), while type alternatives keep `case`; `extern fn`. `with` is not part of this change.

The parser answers each Python word with a targeted diagnostic (`def`, `lambda`, `elif`, `True`/`False`/`None`, `Callable[...]`, `f"..."`, `from ... import`, `case` arms, `()`, `->`, `a if c else b`); keep those messages when touching the parser, and the `foreign-*` conformance fixtures record them.

Apply when: changing keywords, adding a construct that resembles a Python one, or writing examples and prompts. Do not reintroduce Python spellings to save tokens or to look familiar.
Evidence: [grammar](../../documentation/core-language/basics/grammar.md), [proposal](../../proposals/surface-syntax-distinct.md), `tests/conformance/fixtures/snippets/foreign-*`.
Verify: `ms check` on `def f() -> Int:`, `lambda x: x`, `True`, `elif`, `f"x"` each reports the targeted fix; `ms guide` shows only the new forms.

---
Topics: [Syntax and parsing](../topics/syntax-and-parsing.md)
