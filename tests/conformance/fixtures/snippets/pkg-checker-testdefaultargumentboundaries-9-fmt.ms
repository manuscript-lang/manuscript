# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:22 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value
fn call() Int:
    let copy: fn(value: Int) Int = f
    return copy()
