// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/result_lint_test.go:29 TestDiscardedResultLint
type Outcome {
	value Int
}

fn caller() Void {
	Outcome(1)
}
// expect-exit: 0
