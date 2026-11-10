// conform: tags=diagnostics,lists,match,optional,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_match_test.go:11 TestFormatMatchExpressions
fn read(values: List[Int]) Int:
    result := match values.first():
        number:
            doubled := number * 2
            doubled
        none: return 0

    return result
