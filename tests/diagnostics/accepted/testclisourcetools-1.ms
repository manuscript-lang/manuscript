// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/e2e_test.go:338 TestCLISourceTools
fn one() Int {
	return 1  // keep
}
// expect-exit: 0
