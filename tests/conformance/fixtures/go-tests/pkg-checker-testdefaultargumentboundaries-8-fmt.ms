# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:21 TestDefaultArgumentBoundaries
fn f[T](value: T, copy: T = value) T:
    return copy
fn call() Int:
    return f()
