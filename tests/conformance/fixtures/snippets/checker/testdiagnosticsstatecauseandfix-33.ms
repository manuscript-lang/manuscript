// conform: tags=alternatives,diagnostics,generics,match,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:52 TestDiagnosticsStateCauseAndFix
enum Choice[T] {
	Found(value T)
	Missing
}

fn f(c Choice[Int]) Int {
	match c {
		Choice[String].Found(v) => return 1
		Choice[String].Missing => return 0
	}
}
// expect-error: MS3000 11:9 pattern belongs to a different alternative; qualify arms with the matched type, Choice.<case>
// expect-error: MS3000 12:9 pattern belongs to a different alternative; qualify arms with the matched type, Choice.<case>
