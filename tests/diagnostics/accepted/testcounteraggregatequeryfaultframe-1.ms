// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/counter_aggregate_test.go:166 TestCounterAggregateQueryFaultFrame
fn probe() Int {
	var sum = 0
	var i = 0

	while i < 321 {
		sum += i
		i += 1
	}

	return sum
}
// expect-exit: 0
