# conform: tags=lists,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:113 TestPartialMatchExpressionPositions
fn broken(
fn later(values: List[Int]) Int:
    let result = match values[0]:
        some(number):
            let doubled = number * 2
            doubled
        none: return 0
    return result
