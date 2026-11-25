// conform: tags=formatter,match,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/format/format_layout_test.go:214 TestFormatExpressionLayouts
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
// expect-format-exit: 1
