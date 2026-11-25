// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/defaults_test.go:18 TestDefaultArgumentBoundaries
fn f(value Int = 1) Int {
	return value
}

fn call() Int {
	return f(2, value: 3)
}
// expect-error: MS3002 9:17 duplicate argument value; pass each argument once
