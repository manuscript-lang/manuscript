# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:653 TestTypeBoundaries
def old[T: MissingBound](value: T) -> T:
    return value
