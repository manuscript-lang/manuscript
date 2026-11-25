// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/defaults_test.go:16 TestDefaultArgumentBoundaries
fn f(value Int = value) Int {
	return value
}
// expect-error: MS2001 4:18 unknown binding value; declare it with 'value := ...' before use, define 'fn value(...) T { ... }', or import it from a module
