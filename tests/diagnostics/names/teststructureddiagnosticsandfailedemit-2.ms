// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/cli_test.go:152 TestStructuredDiagnosticsAndFailedEmit
fn value() Int {
	return unknown
}
// expect-error: MS2001 5:12 unknown binding unknown; declare it with 'unknown := ...' before use, define 'fn unknown(...) T { ... }', or import it from a module
