// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:24 TestDefaultArgumentBoundaries
fn f(value Int = 1) Int {
	return value
}

fn apply(callback fn(Int) Int) Int {
	return callback()
}
// expect-error: MS3003 9:12 missing argument 1: Int in call to callback; pass it positionally, without a label
