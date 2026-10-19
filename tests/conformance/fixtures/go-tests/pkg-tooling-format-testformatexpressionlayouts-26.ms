# conform: tags=diagnostics,match,optional,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:223 TestFormatExpressionLayouts
fn work(early: Int) Int:
    let result = subtract(
        try match some(0):
            some(_):
                10
            none: 10
    )
    return result
