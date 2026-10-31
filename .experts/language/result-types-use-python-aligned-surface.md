[Wiki](../index.md) › [Language](index.md)

# Result types use `->` (Python-aligned surface)

Superseded (2026-10-28): the surface is deliberately distinct from Python again, see [Surface syntax is its own, not Python's](#surface-syntax-is-its-own-not-pythons). Earlier: the Python-aligned grammar (see [the final delta](../../documentation/core-language/basics/grammar.md)) restores `->` before result types, spells function types `Callable[[Int], Int]`, and makes parameter names in function types documentation only. The earlier decision follows for history.

Decision (superseded): the user asked to drop `->` before result types to save tokens (about 1% of source tokens measured with cl100k over the stdlib, accept tests, and examples; colons and `name: Type` were left alone). Named functions, methods, interface operations, and function types still require the result type (`def f(x: Int) -> Int:`, `Callable[[Int], Int]`); lambdas may omit it and the parser reads a type after `)` as the result type and `:` as the body. `->` is a lexer token only so the parser can say to remove it. Call labels, map entries, and inline suites keep `:` because no separator would make `f(a [1])`, `a (b)`, and `a -1` unambiguous. `ms fmt` reformats migrated files because shorter lines rewrap.

Decision: the same spelling applies to displayed types, including LSP hover. Keep the shared type formatter ([types](../../crates/ms-check/src/types.rs)) consistent with source syntax; hover, completions, diagnostics, and API snapshots consume it. Consumers that parse displayed signatures must skip nested callback parameter lists before reading the outer result.

Apply when: changing function type syntax, displayed signatures, or anything that parses a displayed type.
Evidence: [grammar](../../documentation/core-language/basics/grammar.md).
Verify: a callback returning a Result inside a function that does not return one is extracted with the outer result, not the callback's.

---
Topics: [Syntax and parsing](../topics/syntax-and-parsing.md)
