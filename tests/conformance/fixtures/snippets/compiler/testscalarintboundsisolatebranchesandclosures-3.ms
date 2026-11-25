// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/int_bounds_test.go:67 TestScalarIntBoundsIsolateBranchesAndClosures
fn probe(value Int, flag Bool) Int {
	var sum = 0
	if flag {
		sum = value
	}
	sum += 1
	return sum
}
// expect-exit: 0
