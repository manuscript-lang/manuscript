# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:655 TestTypeBoundaries
def invalid(value: Callable[[], Int]) -> Bool:
    return value == value
