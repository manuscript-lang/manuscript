// conform: tags=control-flow,diagnostics,faults,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/list_items_test.go:38 TestListItemsCacheKeepsDebugAndLocalsOrdinary
fn work() Int {
	values := [1, 2]
	var i = 0
	var total = 0

	while i < 2 {
		total += values[i]
		i += 1
	}

	return total
}
// expect-exit: 0
