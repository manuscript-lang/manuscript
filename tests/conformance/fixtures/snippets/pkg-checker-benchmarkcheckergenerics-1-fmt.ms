# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/performance_test.go:67 BenchmarkCheckerGenerics
def identity[T](value: T) -> T: value

def use() -> Unit: ...
