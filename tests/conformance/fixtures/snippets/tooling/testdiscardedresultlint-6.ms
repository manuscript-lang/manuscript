// conform: tags=diagnostics,match,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/result_lint_test.go:20 TestDiscardedResultLint
fn caller() Void {
	match operation() {
		ok(value) => operation()
		error(cause) => operation()
	}
}
// expect-error: MS2001 5:11 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
