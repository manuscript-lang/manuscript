// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/analysis_test.go:168 TestAnalysisProjectScopes
// Local value.
export fn value() Int {
	return 0
}
// expect-exit: 0
