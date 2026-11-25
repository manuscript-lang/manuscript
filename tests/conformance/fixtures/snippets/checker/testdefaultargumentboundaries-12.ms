// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/defaults_test.go:25 TestDefaultArgumentBoundaries
fn f(value Int = 1) Int {
	return value
}

fn make() fn(Int) Int {
	return f
}

fn call() Int {
	return make()()
}
// expect-error: MS3003 13:12 missing argument 1: Int; pass it positionally, without a label
