// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/review_test.go:121 TestDiagramASCIIIsAnOrderedOutline
fn one() Int {
	return 1
}

fn two() Int {
	return one() + one()
}
// expect-exit: 0
