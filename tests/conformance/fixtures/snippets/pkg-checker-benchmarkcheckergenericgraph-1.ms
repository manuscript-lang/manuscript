# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/performance_test.go:166 BenchmarkCheckerGenericGraph
def f0[T](value: T) -> T: value
