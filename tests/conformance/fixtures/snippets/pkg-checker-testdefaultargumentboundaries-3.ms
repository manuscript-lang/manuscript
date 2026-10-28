# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:16 TestDefaultArgumentBoundaries
fn f(value: Int = value) Int:
    return value
