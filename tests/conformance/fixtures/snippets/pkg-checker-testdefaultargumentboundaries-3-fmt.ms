# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:16 TestDefaultArgumentBoundaries
def f(value: Int = value) -> Int:
    return value
