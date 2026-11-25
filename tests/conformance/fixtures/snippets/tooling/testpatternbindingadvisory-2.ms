// conform: tags=diagnostics,match,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/pattern_lint_test.go:23 TestPatternBindingAdvisory
type Item {
	value Int
}

fn use(value Item?) Int {
	match value {
		item => return Item.value
		null => return 0
	}
}
// expect-error: MS2001 10:29 Item has no member value; a type name is followed only by an enum case
