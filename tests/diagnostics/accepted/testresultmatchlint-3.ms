// conform: tags=control-flow,diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/result_match_lint_test.go:16 TestResultMatchLint
fn use(value Int!) Int {
	if n := value {
		return n
	}
	return 0
}
// expect-exit: 0
