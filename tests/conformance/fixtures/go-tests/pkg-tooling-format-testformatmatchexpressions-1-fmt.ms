# conform: tags=formatter,lists,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_match_test.go:11 TestFormatMatchExpressions
fn read(values: List[Int]) Int:
    let result=match values.first():
        some(number):
            let doubled=number*2
            doubled
        none: return 0
    return result
