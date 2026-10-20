# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:59 TestPartialDefaultsPreserveExpressionPositions
fn broken(
fn later(first: Int = 3, second: Int = first + 1) Int:
    return second
