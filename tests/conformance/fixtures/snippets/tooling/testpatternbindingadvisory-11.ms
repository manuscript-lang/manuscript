// conform: tags=alternatives,diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/pattern_lint_test.go:42 TestPatternBindingAdvisory
enum Failure {
	NotFound
}

fn use() Int {
	NotFound := 1
	return NotFound
}
// expect-exit: 0
