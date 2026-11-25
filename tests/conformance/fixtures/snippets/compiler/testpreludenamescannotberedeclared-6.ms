// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:115 TestPreludeNamesCannotBeRedeclared
fn List(value Int) Int => value
// expect-error: MS2001 4:1 declaration List reuses a prelude name; rename it, because List always refers to the standard declaration
