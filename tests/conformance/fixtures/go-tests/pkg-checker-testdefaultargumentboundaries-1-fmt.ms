# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:14 TestDefaultArgumentBoundaries
fn f(value: Int = true) Int:
    return value
