// conform: tags=diagnostics
// conform: phase=check
fn f(value Int = 1) Int {
	return value
}

fn call() Int {
	copy fn(Int) Int := f
	return copy()
}
// expect-error: MS3003 9:12 missing argument 1: Int in call to copy; pass it positionally, without a label
