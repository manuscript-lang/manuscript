# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:406 TestFormatExpressionLayouts
def work() -> Int:
    return apply(value: 3, transform: lambda (value: Int) -> Int: return value + 1)
