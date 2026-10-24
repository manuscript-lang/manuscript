# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:22 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def call() -> Int:
    let copy: Callable[[Int], Int] = f
    return copy()
