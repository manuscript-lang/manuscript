// conform: tags=diagnostics,mutation,tier-core
// conform: phase=check
// conform: origin=pkg/checker/defaults_test.go:23 TestDefaultArgumentBoundaries
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
// expect-error: MS3003 15:12 missing argument 1: Int in call to copy; pass it positionally, without a label
