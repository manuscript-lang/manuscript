// conform: tags=control-flow,diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/optional_match_lint_test.go:16 TestOptionalMatchLint
fn use(value Int?) Int {
	n := value
	if n != null { return n }

	return 0
}
// expect-exit: 0
