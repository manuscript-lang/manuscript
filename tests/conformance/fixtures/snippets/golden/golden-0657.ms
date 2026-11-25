// conform: tags=diagnostics
// conform: phase=check
type List[T] {
	value T
}

fn f() Void {
	xs := [1]
}
// expect-error: MS2001 3:1 declaration List reuses a prelude name; rename it, because List always refers to the standard declaration
