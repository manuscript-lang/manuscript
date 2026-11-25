// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/performance_test.go:31 BenchmarkGo
fn work() Int => return 1
// expect-exit: 0
