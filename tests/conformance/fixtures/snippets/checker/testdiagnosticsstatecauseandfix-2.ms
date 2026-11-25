// conform: tags=diagnostics,faults,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:21 TestDiagnosticsStateCauseAndFix
fn f() Void {
	return panic(message: "x")
}
// expect-error: MS2001 5:12 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
