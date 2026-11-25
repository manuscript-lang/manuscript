// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/int_bounds_test.go:244 BenchmarkCounterAggregateScaling
fn probe() Int {
	var sum = 0
	unrelated := 7
}
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
