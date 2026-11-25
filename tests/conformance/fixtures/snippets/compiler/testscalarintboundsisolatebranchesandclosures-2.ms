// conform: tags=closures,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/int_bounds_test.go:60 TestScalarIntBoundsIsolateBranchesAndClosures
fn probe(value Int) Int {
	var sum = 0
	sum = value

	callback := fn() Int {
		return sum + value
	}
	return callback()
}
// expect-exit: 0
