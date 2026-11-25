// conform: tags=closures,diagnostics,match,optional,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/nested_match_lint_test.go:22 TestNestedMatchLint
fn use(value Int?) Int {
	return match value {
		_value => {
			callback := fn(
				n Int = match value {
					x => x
					null => 0
				}
			) Int {
				return n
			}
			callback()
		}
		null => 0
	}
}
