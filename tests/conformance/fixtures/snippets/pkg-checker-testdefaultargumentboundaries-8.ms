# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:21 TestDefaultArgumentBoundaries
fn f[T](value: T, copy: T = value) T:
    return copy

fn call() Int:
    return f()
