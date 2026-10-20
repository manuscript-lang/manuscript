# conform: tags=formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:23 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value
fn g(value: Int) Int:
    return value
fn call() Int:
    var copy = f
    copy = g
    return copy()
