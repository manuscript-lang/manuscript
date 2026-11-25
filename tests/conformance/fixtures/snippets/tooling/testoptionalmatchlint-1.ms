// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/optional_match_lint_test.go:14 TestOptionalMatchLint
fn use(value Int?) Int {
	match value {
		n => return n
		null => return 0
	}
}
// expect-exit: 0
