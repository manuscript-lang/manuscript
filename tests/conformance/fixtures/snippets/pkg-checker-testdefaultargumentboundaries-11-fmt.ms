# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:24 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def apply(callback: Callable[[Int], Int]) -> Int:
    return callback()
