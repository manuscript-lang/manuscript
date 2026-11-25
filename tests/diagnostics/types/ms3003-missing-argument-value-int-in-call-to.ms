// conform: tags=diagnostics
// conform: phase=check
fn f[T](value T, copy T = value) T {
	return copy
}

fn call() Int {
	return f()
}
// expect-error: MS3003 8:12 missing argument value: Int in call to f; add 'value: <Int>'
