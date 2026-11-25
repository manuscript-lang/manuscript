// conform: tags=formatter,lists,maps,match,optional,parser,strings,tier-core
// conform: phase=parse
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
