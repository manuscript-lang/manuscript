# conform: tags=closures,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:28 TestDefaultArgumentBoundaries
def run[T](operation: Callable[[], T]) -> T:
    return operation()

def f(value: Int = 1) -> Int:
    return value

def call() -> Int:
    return run(f)
