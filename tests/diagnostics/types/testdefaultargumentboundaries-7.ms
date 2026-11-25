// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:20 TestDefaultArgumentBoundaries
fn f[T](value T = 3) T {
	return value
}
// expect-error: MS3001 4:19 expected T, found Int
