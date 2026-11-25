// conform: tags=diagnostics
// conform: phase=check
fn id[T](x T) T {
	return x
}

fn f() Int {
	g := id
	return g(1)
}
// expect-error: MS3000 8:10 a generic function value requires explicit specialization; write id[Type] or call it with arguments
