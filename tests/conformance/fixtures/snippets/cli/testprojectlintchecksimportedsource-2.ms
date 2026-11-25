// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/cli_test.go:233 TestProjectLintChecksImportedSource
export fn value() Int {
	return 3
}
// expect-exit: 0
