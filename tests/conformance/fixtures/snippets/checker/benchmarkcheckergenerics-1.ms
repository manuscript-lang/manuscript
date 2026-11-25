// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/performance_test.go:67 BenchmarkCheckerGenerics
fn identity[T](hold value T) &T => value

fn use() Void { ... }
// expect-exit: 0
