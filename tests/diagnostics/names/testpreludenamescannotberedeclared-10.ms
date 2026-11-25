// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:119 TestPreludeNamesCannotBeRedeclared
fn error(value Int) Int => value
// expect-error: MS2001 4:1 declaration error reuses a prelude constructor name; rename it, because error always refers to the prelude case
