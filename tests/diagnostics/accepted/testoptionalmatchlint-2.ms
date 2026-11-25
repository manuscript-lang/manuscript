// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/optional_match_lint_test.go:15 TestOptionalMatchLint
fn use(value Int?) Int {
	return match value {
		n => n
		null => 0
	}
}
// expect-exit: 0
