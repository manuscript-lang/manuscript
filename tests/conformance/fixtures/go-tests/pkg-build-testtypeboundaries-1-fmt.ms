# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:653 TestTypeBoundaries
fn old[T: MissingBound](value: T) T:
    return value
