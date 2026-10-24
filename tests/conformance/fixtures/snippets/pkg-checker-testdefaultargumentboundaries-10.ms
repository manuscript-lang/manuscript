# conform: tags=diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:23 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def g(value: Int) -> Int:
    return value

def call() -> Int:
    var copy = f
    copy = g
    return copy()
