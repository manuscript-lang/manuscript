// conform: tags=diagnostics,records,sets,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:112 TestPreludeNamesCannotBeRedeclared
type Set[T] {
	value T
}
// expect-error: MS2001 4:1 declaration Set reuses a prelude name; rename it, because Set always refers to the standard declaration
