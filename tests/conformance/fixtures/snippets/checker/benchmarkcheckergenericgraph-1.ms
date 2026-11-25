// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/performance_test.go:166 BenchmarkCheckerGenericGraph
fn f0[T](hold value T) &T => value
// expect-exit: 0
