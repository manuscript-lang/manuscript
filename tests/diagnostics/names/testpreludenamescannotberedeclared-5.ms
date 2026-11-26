// conform: tags=diagnostics,formatter,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:114 TestPreludeNamesCannotBeRedeclared
interface Equal {
	fn same() Bool
}
// expect-error: MS2001 4:1 declaration Equal reuses a prelude name; rename it, because Equal always refers to the standard declaration
