# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:15 TestDefaultArgumentBoundaries
def f(first: Int = second, second: Int = 2) -> Int:
    return first
