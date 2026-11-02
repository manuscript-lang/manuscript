# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/performance_test.go:166 BenchmarkCheckerGenericGraph
fn f0[T](value: T) T: value
