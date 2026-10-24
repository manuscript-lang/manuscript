# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:24 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def apply(callback: Callable[[Int], Int]) -> Int:
    return callback()
