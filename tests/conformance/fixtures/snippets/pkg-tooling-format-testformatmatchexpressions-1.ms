# conform: tags=diagnostics,lists,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_match_test.go:11 TestFormatMatchExpressions
def read(values: List[Int]) -> Int:
    let result = match values.first():
        case some(number):
            let doubled = number * 2
            doubled
        case none: return 0

    return result
