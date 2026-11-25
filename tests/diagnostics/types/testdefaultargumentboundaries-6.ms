// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:19 TestDefaultArgumentBoundaries
fn f(value Int = 1) Int {
	return value
}

fn call() Int {
	return f(other: 3)
}
// expect-error: MS3004 9:14 unknown argument other; parameters of f: value
