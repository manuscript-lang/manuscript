# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:14 TestDefaultArgumentBoundaries
def f(value: Int = True) -> Int:
    return value
