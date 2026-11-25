// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/e2e_test.go:363 TestCLISourceTools
fn wrong() Int {
	return missing
}
// expect-error: MS2001 5:12 unknown binding missing; declare it with 'missing := ...' before use, define 'fn missing(...) T { ... }', or import it from a module
