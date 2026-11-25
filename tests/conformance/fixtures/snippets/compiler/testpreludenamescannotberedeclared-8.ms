// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:117 TestPreludeNamesCannotBeRedeclared
fn ok(value Int) Int => value
// expect-error: MS2001 4:1 declaration ok reuses a prelude constructor name; rename it, because ok always refers to the prelude case
