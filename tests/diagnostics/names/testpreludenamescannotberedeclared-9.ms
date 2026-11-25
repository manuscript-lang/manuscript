// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:118 TestPreludeNamesCannotBeRedeclared
fn null() Int => 1
// expect-error: MS2001 4:1 declaration null reuses a prelude constructor name; rename it, because null always refers to the prelude case
