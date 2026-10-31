# conform: tags=formatter,match,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:223 TestFormatExpressionLayouts
fn work(early: Int) Int:
    let result = subtract(
        try match 0:
            _value:
                10
            none: 10
    )
    return result
