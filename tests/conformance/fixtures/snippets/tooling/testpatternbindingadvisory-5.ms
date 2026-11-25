// conform: tags=alternatives,diagnostics,formatter,match,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/pattern_lint_test.go:27 TestPatternBindingAdvisory
enum First {
	Ready
}

enum Second {
	Ready
}

fn use(value Int?) Int {
	match value {
		ready => return Ready
		null => return 0
	}
}
// expect-error: MS2001 14:25 ambiguous alternative case Ready; qualify it with its type, e.g. Type.Ready
