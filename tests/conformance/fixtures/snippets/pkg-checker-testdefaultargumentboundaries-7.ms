# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:20 TestDefaultArgumentBoundaries
def f[T](value: T = 3) -> T:
    return value
