// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:118 TestPreludeNamesCannotBeRedeclared
fn null() Int => 1
// expect-error: MS2001 4:1 declaration null reuses a prelude constructor name; rename it, because null always refers to the prelude case
