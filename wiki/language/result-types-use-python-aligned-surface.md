[Wiki](../index.md) › [Language](index.md)

# Result types use `->` (Python-aligned surface)

Superseded (2026-10-28): the surface is deliberately distinct from Python again, see [Surface syntax is its own, not Python's](#surface-syntax-is-its-own-not-pythons). Earlier: the Python-aligned grammar (see [the final delta](../../documentation/core-language/basics/grammar.md)) restores `->` before result types, spells function types `Callable[[Int], Int]`, and makes parameter names in function types documentation only. The earlier decision follows for history.

Apply when: changing function type syntax, displayed signatures, or anything that parses a displayed type.
Evidence: [grammar](../../documentation/core-language/basics/grammar.md).
Verify: a callback returning a Result inside a function that does not return one is extracted with the outer result, not the callback's.
