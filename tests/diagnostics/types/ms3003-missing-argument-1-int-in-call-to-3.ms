// conform: tags=diagnostics
// conform: phase=check
fn f(value Int = 1) Int {
	return value
}

fn g(value Int) Int {
	return value
}

fn call() Int {
	var copy = f
	copy = g
	return copy()
}
// expect-error: MS3003 14:12 missing argument 1: Int in call to copy; pass it positionally, without a label
