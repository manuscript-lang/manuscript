# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:19 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def call() -> Int:
    return f(other: 3)
