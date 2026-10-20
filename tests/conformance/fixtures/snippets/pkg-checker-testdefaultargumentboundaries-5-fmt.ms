# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:18 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value
fn call() Int:
    return f(2, value: 3)
