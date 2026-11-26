// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/diff_test.go:61 TestRemovedContent
fn a() Int {
	return 0
}
// expect-exit: 0
