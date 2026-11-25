// conform: tags=diagnostics
// conform: phase=check
fn g[T](x T) Int {
	return 0
}

fn f() Int {
	return g()
}
// expect-error: MS3080 8:12 cannot infer type argument T for g; write g[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
