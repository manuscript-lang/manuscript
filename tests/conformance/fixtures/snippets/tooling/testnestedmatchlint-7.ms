// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/nested_match_lint_test.go:27 TestNestedMatchLint
fn use(value Int?) Int {
	present := match value {
		n => n
		null => return 0
	}

	return match value {
		n => present + n
		null => 0
	}
}
// expect-exit: 0
