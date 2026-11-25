// conform: tags=diagnostics
// conform: phase=check
fn f(value Int = 1) Int {
	return value
}

fn forward[T](value T) T {
	return value
}

fn call() Int {
	copy := forward(f)
	return copy()
}
// expect-error: MS3003 13:12 missing argument 1: Int in call to copy; pass it positionally, without a label
