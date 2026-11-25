// conform: tags=alternatives,control-flow,diagnostics,formatter,interfaces,match,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/pattern_lint_test.go:29 TestPatternBindingAdvisory
interface Describe {
	fn describe() String
}

enum State {
	Ready
	Waiting
}

fn State.describe() String => "state"

fn use(value Describe) Int {
	match value {
		State(Ready) => return 1
		_ => return 0
	}
}
// expect-exit: 0
