# conform: tags=closures,control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:415 TestFormatExpressionLayouts
fn work() Int:
    return apply(value: 3, transform: fn(value: Int) Int:
        if value == 0: return 0
        let next = value + 1
        return next
    )
