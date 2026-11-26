// conform: tags=diagnostics,formatter,lists,maps,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:26 TestDiagnosticFixes
fn f() Int {
	m := Map[List[Int], Int]()
	return 0
}
// expect-error: MS3021 5:10 List[Int] does not satisfy Hashable; collections have no Hashable implementation, so use a type as the key or join the elements into a String
