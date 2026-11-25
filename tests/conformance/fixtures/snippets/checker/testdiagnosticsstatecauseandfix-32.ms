// conform: tags=alternatives,diagnostics,formatter,generics,match,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:51 TestDiagnosticsStateCauseAndFix
enum Choice[T] {
	Found(value T)
	Missing
}

fn f(c Choice[Int], o Int?) Int {
	match o {
		Optional.some(n) => return n
		Optional.null => return 0
	}

	match c {
		Choice.Found(v) => return v
		Choice.Missing => return 0
	}
}
// expect-exit: 0
