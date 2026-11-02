[Wiki](../index.md) › [Language](index.md)

# Surface syntax is its own, not Python's

Decision (user, 2026-10-28): agents slip into Python when the surface looks like Python (the Haiku bench logged 20 capitalized `True`/`False` errors), so the surface now differs on purpose.

The parser answers each Python word with a targeted diagnostic (`def`, `lambda`, `elif`, `True`/`False`/`None`, `Callable[...]`, `f"..."`, `from ... import`, `case` arms, `()`, `->`, `a if c else b`); keep those messages when touching the parser, and the `foreign-*` conformance fixtures record them.


Apply when: changing keywords, adding a construct that resembles a Python one, or writing examples and prompts. Do not reintroduce Python spellings to save tokens or to look familiar.
Evidence: [grammar](../../documentation/core-language/basics/grammar.md), [proposal](../../proposals/surface-syntax-distinct.md), `tests/conformance/fixtures/snippets/foreign-*`.
Verify: `ms check` on `def f() -> Int:`, `lambda x: x`, `True`, `elif`, `f"x"` each reports the targeted fix; `ms guide` shows only the new forms.
