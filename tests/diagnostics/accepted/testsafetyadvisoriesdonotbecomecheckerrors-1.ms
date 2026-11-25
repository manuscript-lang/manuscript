// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/advisory_lint_test.go:16 TestSafetyAdvisoriesDoNotBecomeCheckErrors
fn use(value Int?) Void {
	match value {
		_value => {
			match value {
				_value => void
				null => void
			}
		}
		null => void
	}
}
// expect-exit: 0
