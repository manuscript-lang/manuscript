# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:24 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value
fn apply(callback: fn(value: Int) Int) Int:
    return callback()
