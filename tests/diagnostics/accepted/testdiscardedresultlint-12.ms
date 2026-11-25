// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/result_lint_test.go:26 TestDiscardedResultLint
fn operation() Void! => ok()

fn caller() Int! {
	operation()?
	return ok(1)
}
// expect-exit: 0
