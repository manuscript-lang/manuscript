[Wiki](../index.md) › [Language](index.md)

# One-line bodies and arms use a fat arrow

Decision (Chinmay, 2026-11-24): `=>` introduces one expression: a one-line function body (`fn f(x Int) Int => x + 1`), a match arm (`Some(v) => v`) and a closure (`x => f(x)`, `(a, b) => a + b`, `() => 1`). A closure with typed parameters or a result keeps `fn` (`fn(v Int) Int => v - 1`). A longer body keeps `:` and indented lines until the brace change lands. `if c: a else: b` and one-line `if` or loop bodies still use `:`.

Apply when: parsing or formatting closures, arms or function bodies, writing examples, or changing diagnostics that show a closure.
Evidence: [proposal](../../proposals/braces-and-typed-names.md), [removed spellings](../../../documentation/core-language/removed-spellings.md), `lambda_expression` and `statement_suite_inner` in `src/compiler/syntax`.
Verify: `x =>` is a closure only where a name or a parenthesized list is followed by `=>`; `(a)` alone stays a grouped expression; an arm pattern is never read as a closure parameter; a closure inside an f-string interpolation migrates with the interpolation's source offset added.
