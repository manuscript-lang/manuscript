# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:20 TestDefaultArgumentBoundaries
fn f[T](value: T = 3) T:
    return value
