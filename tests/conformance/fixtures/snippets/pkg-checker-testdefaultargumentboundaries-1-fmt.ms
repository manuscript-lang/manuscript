# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:14 TestDefaultArgumentBoundaries
def f(value: Int = True) -> Int:
    return value
