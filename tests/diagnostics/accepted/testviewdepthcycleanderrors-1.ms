// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/views_test.go:43 TestViewDepthCycleAndErrors
fn a(n Int) Int {
	return b(n)
}

fn b(n Int) Int {
	return a(n)
}
// expect-exit: 0
