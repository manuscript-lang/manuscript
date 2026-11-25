// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/cli_test.go:277 TestSourceCommandsRetainProjectEntryValidation
export fn helper() Int {
	return 1
}
// expect-exit: 0
