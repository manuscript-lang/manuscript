// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/test_fixture_test.go:177 TestCLITestFixturesStayLocalToEachFile
export fn helper() Void {
	return
}
// expect-exit: 0
