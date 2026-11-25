// conform: tags=diagnostics,formatter,generics,records,sets,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:78 TestCollectionPreludeAndShadowing
type Set[T] {
	value T
}

fn f(values Set[Int]) Void {
	values.add(1)
}
// expect-error: MS2001 4:1 declaration Set reuses a prelude name; rename it, because Set always refers to the standard declaration
