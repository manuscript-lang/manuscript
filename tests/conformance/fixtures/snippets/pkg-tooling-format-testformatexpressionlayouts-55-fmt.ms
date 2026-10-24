# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:406 TestFormatExpressionLayouts
def work() -> Int:
    return apply(value: 3, transform: lambda (value: Int) -> Int: return value + 1)
