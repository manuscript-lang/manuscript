// conform: tags=diagnostics,formatter,numbers,sets,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:25 TestDiagnosticFixes
fn f() Int {
	s := Set[Float]()
	return 0
}
// expect-error: MS3021 5:10 Float does not satisfy Hashable; Float has no Hashable implementation, so wrap it in a type with an Int or String key, or use Decimal
