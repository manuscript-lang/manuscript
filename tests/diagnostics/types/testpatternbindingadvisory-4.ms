// conform: tags=alternatives,diagnostics,formatter,match,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/pattern_lint_test.go:26 TestPatternBindingAdvisory
enum Flag {
	Ready
}

fn use(value Int?) Int {
	match value {
		ready => return Ready
		null => return 0
	}
}
// expect-error: MS3001 10:25 expected Int, found Flag (in the return value)
