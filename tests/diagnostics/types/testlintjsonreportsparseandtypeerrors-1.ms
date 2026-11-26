// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/cli_test.go:345 TestLintJSONReportsParseAndTypeErrors
export fn main() Int {
	return "a"
}
// expect-error: MS3001 5:12 expected Int, found String (in the return value)
