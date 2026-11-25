// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:110 TestPreludeNamesCannotBeRedeclared
type Optional {
	value Int
}
// expect-error: MS2001 4:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
