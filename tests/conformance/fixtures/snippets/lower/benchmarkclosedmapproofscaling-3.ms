// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/lower/int_bounds_test.go:167 BenchmarkClosedMapProofScaling
fn probe() Int { ... }
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
