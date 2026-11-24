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
