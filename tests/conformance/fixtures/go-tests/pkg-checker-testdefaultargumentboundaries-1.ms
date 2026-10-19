# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:14 TestDefaultArgumentBoundaries
fn f(value: Int = true) Int:
    return value
