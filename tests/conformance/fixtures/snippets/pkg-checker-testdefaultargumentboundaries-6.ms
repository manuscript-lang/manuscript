# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:19 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def call() -> Int:
    return f(other: 3)
