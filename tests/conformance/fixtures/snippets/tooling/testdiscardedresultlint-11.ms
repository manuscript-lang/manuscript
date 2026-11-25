// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/result_lint_test.go:25 TestDiscardedResultLint
fn caller() Void {
	_ignored := operation()
}
// expect-error: MS2001 5:17 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
