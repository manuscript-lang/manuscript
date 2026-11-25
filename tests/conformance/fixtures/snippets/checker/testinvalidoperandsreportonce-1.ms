// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/invalid_operand_test.go:16 TestInvalidOperandsReportOnce
fn f() Int {
	x := nope
	return x + x
}
// expect-error: MS2001 5:10 unknown binding nope; declare it with 'nope := ...' before use, define 'fn nope(...) T { ... }', or import it from a module
