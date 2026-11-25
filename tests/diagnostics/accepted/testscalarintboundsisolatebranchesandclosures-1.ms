// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/int_bounds_test.go:52 TestScalarIntBoundsIsolateBranchesAndClosures
fn probe(value Int, flag Bool) Int {
	var sum = value

	if flag {
		sum = 0
	} else {
		sum += 1
	}

	return sum
}
// expect-exit: 0
