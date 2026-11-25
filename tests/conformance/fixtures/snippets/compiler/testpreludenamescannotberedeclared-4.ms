// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:113 TestPreludeNamesCannotBeRedeclared
type ListEntry {
	value Int
}
// expect-error: MS2001 4:1 declaration ListEntry reuses a prelude name; rename it, because ListEntry always refers to the standard declaration
