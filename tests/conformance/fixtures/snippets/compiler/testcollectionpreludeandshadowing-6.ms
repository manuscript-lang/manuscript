// conform: tags=diagnostics,generics,lists,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:68 TestCollectionPreludeAndShadowing
type List[T] {
	value T
}

fn f() Void {
	xs := [1]
}
// expect-error: MS2001 4:1 declaration List reuses a prelude name; rename it, because List always refers to the standard declaration
