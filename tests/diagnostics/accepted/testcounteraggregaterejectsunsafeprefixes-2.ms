// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_aggregate_test.go:52 TestCounterAggregateRejectsUnsafePrefixes
fn probe() Int {
	var sum = 0
	var i = -9223372036854775808

	while i < -9223372036854775487 {
		sum += i
		i += 1
	}

	return sum
}
// expect-exit: 0
