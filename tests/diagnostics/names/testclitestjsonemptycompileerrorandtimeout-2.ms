// conform: tags=diagnostics,formatter,testing,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/cli_json_test.go:127 TestCLITestJSONEmptyCompileErrorAndTimeout
test "bad" {
	x := unknown_name
}
// expect-error: MS2001 5:10 unknown binding unknown_name; declare it with 'unknown_name := ...' before use, define 'fn unknown_name(...) T { ... }', or import it from a module
