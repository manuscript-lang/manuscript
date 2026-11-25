// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/format_result_test.go:16 TestFormatJSONChecksAndPartialFailures
fn value() Int {
	return 0
}
// expect-exit: 0
