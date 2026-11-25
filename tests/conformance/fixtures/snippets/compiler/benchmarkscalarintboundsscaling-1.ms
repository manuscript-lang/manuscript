// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/int_bounds_test.go:99 BenchmarkScalarIntBoundsScaling
fn probe() Int {
	var sum = 0
}
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
