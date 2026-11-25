// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:15 TestDefaultArgumentBoundaries
fn f(first Int = second, second Int = 2) Int {
	return first
}
// expect-error: MS2001 4:18 unknown binding second; declare it with 'second := ...' before use, define 'fn second(...) T { ... }', or import it from a module
