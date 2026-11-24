// conform: tags=closures,control-flow,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/result_lint_test.go:19 TestDiscardedResultLint
fn caller() Void {
	callback := fn() Void {
		if true {
			operation()
		}
	}
	callback()
}
