// conform: tags=diagnostics,match,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/result_lint_test.go:24 TestDiscardedResultLint
fn caller() Int! {
	return match operation() {
		ok(value) => {
			operation()
			operation()
		}
		error(cause) => operation()
	}
}
// expect-error: MS2001 5:18 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
