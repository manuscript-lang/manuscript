// conform: tags=closures,control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/result_lint_test.go:19 TestDiscardedResultLint
fn caller() Void {
	callback := fn() Void {
		if true {
			operation()
		}
	}
	callback()
}
// expect-error: MS2001 7:13 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
