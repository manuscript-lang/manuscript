// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/nested_match_lint_test.go:26 TestNestedMatchLint
fn use(value Int?) Int {
	return match value {
		_value => {
			match value {
				_value => {
					match value {
						n => n
						null => 0
					}
				}
				null => 0
			}
		}
		null => 0
	}
}
// expect-exit: 0
