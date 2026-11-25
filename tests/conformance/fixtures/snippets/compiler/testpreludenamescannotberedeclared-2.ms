// conform: tags=diagnostics,maps,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:111 TestPreludeNamesCannotBeRedeclared
type Map[K, V] {
	value V
}
// expect-error: MS2001 4:1 declaration Map reuses a prelude name; rename it, because Map always refers to the standard declaration
