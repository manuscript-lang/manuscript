// conform: tags=diagnostics,formatter,lists,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:77 TestStatementMatchDiscardsArmValues
fn f(xs List[Int], o Int?) Void {
	r := match o {
		v => {
			xs.set(index: 0, value: v)
		}
		null => {
			xs.length()
		}
	}
}
// expect-error: MS3001 10:16 expected Void, found Int
