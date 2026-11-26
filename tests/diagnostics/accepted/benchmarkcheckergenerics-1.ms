// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/performance_test.go:67 BenchmarkCheckerGenerics
fn identity[T](hold value T) &T => value

fn use() Void { ... }
// expect-exit: 0
