// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/diagnostic_fixes_test.go:24 TestDiagnosticFixes
type Box[Hashable] {
	v Hashable
}
// expect-error: MS2001 4:10 duplicate or intrinsic type parameter Hashable; choose a different type parameter name
