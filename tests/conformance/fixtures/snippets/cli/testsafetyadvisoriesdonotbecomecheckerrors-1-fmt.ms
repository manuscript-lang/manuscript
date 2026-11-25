// conform: tags=formatter,match,optional,parser,tier-core
// conform: phase=parse
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
