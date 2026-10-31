# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/performance_test.go:67 BenchmarkCheckerGenerics
fn identity[T](value: T) T: value

fn use() Unit: ...
