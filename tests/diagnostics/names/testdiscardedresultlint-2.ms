// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/result_lint_test.go:16 TestDiscardedResultLint
fn caller() Void {
	operation()
}
// expect-error: MS2001 5:5 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
