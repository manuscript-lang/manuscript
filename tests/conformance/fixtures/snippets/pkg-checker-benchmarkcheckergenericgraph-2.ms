# conform: tags=generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/performance_test.go:168 BenchmarkCheckerGenericGraph
fn f%d[T](value: T) T: f%d(f%d(value))
