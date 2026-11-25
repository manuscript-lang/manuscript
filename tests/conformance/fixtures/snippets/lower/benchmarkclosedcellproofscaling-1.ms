// conform: tags=control-flow,diagnostics,interfaces,mutation,records,tier-core
// conform: phase=check
// conform: origin=pkg/lower/int_bounds_test.go:129 BenchmarkClosedCellProofScaling
interface Counter {
	fn bump(by Int) Int
}

type Cell {
	total Int
}

fn Cell.bump(by Int) Int {
	self.total += by
	return self.total
}

fn probe() Int {
	var sum = 0
}
// expect-error: MS3000 17:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
