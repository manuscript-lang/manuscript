// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/invalid_operand_test.go:18 TestInvalidOperandsReportOnce
fn f() Bool {
	x := nope
	return x and x
}
// expect-error: MS2001 5:10 unknown binding nope; declare it with 'nope := ...' before use, define 'fn nope(...) T { ... }', or import it from a module
