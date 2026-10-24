# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:17 TestDefaultArgumentBoundaries
def f(first: Int = 1, second: Int) -> Int:
    return first + second

def call() -> Int:
    return f()
