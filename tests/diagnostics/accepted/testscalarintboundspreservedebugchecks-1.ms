// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/int_bounds_test.go:83 TestScalarIntBoundsPreserveDebugChecks
fn probe() Int {
	var sum = 0
	var i = 0

	while i < 100 {
		sum += i
		i += 1
	}

	return sum
}
// expect-exit: 0
