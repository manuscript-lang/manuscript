// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_aggregate_test.go:44 TestCounterAggregateRejectsUnsafePrefixes
fn probe() Int {
	var sum = 9223372036854775807
	var i = 0

	while i < 321 {
		sum += i
		i += 1
	}

	return sum
}
// expect-exit: 0
