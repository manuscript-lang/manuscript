// conform: tags=diagnostics,match,optional,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/pattern_lint_test.go:25 TestPatternBindingAdvisory
fn use(value Int?) Int {
	match value {
		int => return Int
		null => return 0
	}
}
// expect-error: MS3000 6:23 type name requires a constructor call; write Int(field: value, ...) to build a value
