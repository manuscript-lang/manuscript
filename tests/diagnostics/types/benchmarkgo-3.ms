// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/performance_test.go:38 BenchmarkGo
fn work() Int {
	var value = 0
}
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
