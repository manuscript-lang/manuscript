// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:54 TestDiagnosticsStateCauseAndFix
fn f() Int {
	s := Set[String]()
	return 0
}
// expect-error: MS3000 5:5 local binding s is never read; remove it, use it, or name it with a leading '_' to ignore it
