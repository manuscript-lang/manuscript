// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/analysis_test.go:102 TestLintOrdersSingleFileFindingsBySourcePosition
fn f() Int {
	return 0
}

fn g() Int {
	_x := 1
	return 2
}
// expect-exit: 0
