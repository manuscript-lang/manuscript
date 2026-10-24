# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:655 TestTypeBoundaries
def invalid(value: Callable[[], Int]) -> Bool:
    return value == value
