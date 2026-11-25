// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:14 TestDefaultArgumentBoundaries
fn f(value Int = true) Int {
	return value
}
// expect-error: MS3001 4:18 expected Int, found Bool
