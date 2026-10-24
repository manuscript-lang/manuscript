# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:214 TestFormatExpressionLayouts
def work(early: Int) -> Int:
    let result = subtract(
        try match some(0):
            case some(_):
                10
            case none: 10
    )
    return result
