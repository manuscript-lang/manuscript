# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:17 TestDefaultArgumentBoundaries
fn f(first: Int = 1, second: Int) Int:
    return first + second

fn call() Int:
    return f()
