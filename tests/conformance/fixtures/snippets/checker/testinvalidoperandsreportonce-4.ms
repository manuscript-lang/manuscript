// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/checker/invalid_operand_test.go:19 TestInvalidOperandsReportOnce
fn f() String {
	x := nope
	return "a" + x.foo + x.bar()
}
// expect-error: MS2001 5:10 unknown binding nope; declare it with 'nope := ...' before use, define 'fn nope(...) T { ... }', or import it from a module
