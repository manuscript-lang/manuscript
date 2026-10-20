# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:26 TestDefaultArgumentBoundaries
fn f(value: Int = 1) Int:
    return value
fn forward[T](value: T) T:
    return value
fn call() Int:
    let copy = forward(f)
    return copy()
