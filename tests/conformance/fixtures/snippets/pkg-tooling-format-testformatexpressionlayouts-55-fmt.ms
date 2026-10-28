# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:406 TestFormatExpressionLayouts
fn work() Int:
    return apply(value: 3, transform: fn(value: Int) Int: return value + 1)
