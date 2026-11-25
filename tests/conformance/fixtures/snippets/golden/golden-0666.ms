// conform: tags=diagnostics
// conform: phase=check
type Set[T] {
	value T
}

fn f(values Set[Int]) Void {
	values.add(1)
}
// expect-error: MS2001 3:1 declaration Set reuses a prelude name; rename it, because Set always refers to the standard declaration
