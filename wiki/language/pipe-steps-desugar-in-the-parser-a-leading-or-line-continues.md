[Wiki](../index.md) › [Language](index.md)

# Pipe steps desugar in the parser; a leading `.` or `|` line continues a statement

Decision: Chinmay chose `|` (not `|>`, `?`, UFCS, or `map_error`) to compose free functions and `try` steps without temporaries; `|` earlier rejected as a second spelling for method chaining, but free functions had no flow form. Method chains use `| .m()`, and a bare `| try` unwraps the value so far. Verified: the parser rewrites each step to the plain call or `try` it names, so checking, lowering and diagnostics are unchanged and argument order is the written order (the step head is a name path with no calls).

Apply when: changing operator precedence, line layout, `try`, or call argument binding.
Evidence: [pipe flows](../../documentation/core-language/basics/expressions.md#pipe-flows), [parser](../../crates/ms-syntax/src/parser.rs), and [pipe fixture](../../tests/e2e/testdata/accept/pipe-flow.ms).
Verify: `try parse(text) | double | try check | .to_string_radix(radix: 10)` runs; a continuation line at the wrong indentation is rejected.
