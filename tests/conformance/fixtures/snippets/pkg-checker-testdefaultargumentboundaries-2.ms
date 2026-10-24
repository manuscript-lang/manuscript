# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:15 TestDefaultArgumentBoundaries
def f(first: Int = second, second: Int = 2) -> Int:
    return first
