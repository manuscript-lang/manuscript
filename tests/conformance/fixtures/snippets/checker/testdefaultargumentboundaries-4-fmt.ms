// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/defaults_test.go:17 TestDefaultArgumentBoundaries
fn f(second Int, first Int = 1) Int:
    return first + second

fn call() Int:
    return f()
