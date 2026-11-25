// conform: tags=control-flow,diagnostics,interfaces,numbers,records,sets,tier-core
// conform: phase=check
// conform: origin=pkg/checker/diagnostic_fixes_test.go:27 TestDiagnosticFixes
type K {
	v Float
}

fn K.equals(other K) Bool {
	return true
}

fn f() Int {
	s := Set[K]()
	return 0
}
// expect-error: MS3021 13:10 K does not satisfy Hashable; give K the methods Hashable declares, or use a type that implements it
