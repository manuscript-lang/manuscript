// conform: tags=diagnostics
// conform: phase=check
type Map[K, V] {
	value V
}

fn f() Void {
	xs := {1: 2}
}
// expect-error: MS2001 3:1 declaration Map reuses a prelude name; rename it, because Map always refers to the standard declaration
