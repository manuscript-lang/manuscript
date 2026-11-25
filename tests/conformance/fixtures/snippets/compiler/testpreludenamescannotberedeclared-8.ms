// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:117 TestPreludeNamesCannotBeRedeclared
fn ok(value Int) Int => value
// expect-error: MS2001 4:1 declaration ok reuses a prelude constructor name; rename it, because ok always refers to the prelude case
