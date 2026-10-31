# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:22 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value

fn call() Int:
    let copy: fn(Int) Int = f
    return copy()
