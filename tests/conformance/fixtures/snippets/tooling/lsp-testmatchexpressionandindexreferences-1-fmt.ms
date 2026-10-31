# conform: tags=formatter,lists,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/match_test.go:9 TestMatchExpressionAndIndexReferences
fn read(values: List[Int], index: Int) Int:
    let result = match values.take(index).first():
        number:
            let doubled = number * 2
            doubled
        none: 0

    return result
