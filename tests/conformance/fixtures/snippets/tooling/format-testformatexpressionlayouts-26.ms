// conform: tags=diagnostics,match,optional,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:223 TestFormatExpressionLayouts
fn work(early Int) Int {
    result := subtract(
        match? 0 {
            _value => {
                10
            }
            null => 10
        }
    )
    return result
}
// expect-error: MS1000 6:14-6:15 expected an expression, found '?'; write a value, name, call, or literal here
// expect-error: MS1000 11:9 mismatched closing delimiter '}'; the '(' opened at line 5:23 needs ')'
