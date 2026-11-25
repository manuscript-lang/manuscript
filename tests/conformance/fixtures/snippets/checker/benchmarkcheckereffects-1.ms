// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/performance_test.go:39 BenchmarkCheckerEffects
type Cell {
	value Int
}
// expect-exit: 0
