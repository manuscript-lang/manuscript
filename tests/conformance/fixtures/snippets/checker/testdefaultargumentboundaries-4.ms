// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:17 TestDefaultArgumentBoundaries
fn f(second Int, first Int = 1) Int {
	return first + second
}

fn call() Int {
	return f()
}
// expect-error: MS3003 9:12 missing argument second: Int in call to f; add 'second: <Int>'
