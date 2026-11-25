// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/defaults_test.go:22 TestDefaultArgumentBoundaries
fn f(value Int = 1) Int {
	return value
}

fn call() Int {
	copy fn(Int) Int := f
	return copy()
}
// expect-error: MS3003 10:12 missing argument 1: Int in call to copy; pass it positionally, without a label
