// conform: tags=diagnostics,formatter,lists,maps,match,optional,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:75 TestStatementMatchDiscardsArmValues
fn f(var counts Map[String, Int], var names List[String], found Int?) Void {
	match found {
		n => {
			counts.add(key: "a", value: n)
		}
		null => {
			names.append("x")
		}
	}
}
// expect-exit: 0
