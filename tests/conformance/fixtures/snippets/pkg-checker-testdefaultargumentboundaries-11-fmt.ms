# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:24 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value

fn apply(callback: fn(value: Int) Int) Int:
    return callback()
