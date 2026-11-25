// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/cli_test.go:188 TestFormattingCheckAndPermissionPreservation
fn value() Int {
	return sum(left: read(1), right: 2)
}
// expect-error: MS2001 5:12 unknown binding sum; declare it with 'sum := ...' before use, define 'fn sum(...) T { ... }', or import it from a module
