// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/diagnostic_fixes_test.go:33 TestDiagnosticFixes
type Int {
	x Int
}

fn f() Int {
	t := Int(x: 2)
	return 0
}
// expect-error: MS2001 4:1 duplicate or intrinsic name Int; this name is already declared, imported, or built in, so rename one of them
