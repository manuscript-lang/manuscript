# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:197 TestFormatExpressionLayouts
let prices = [12, 8, 25]
let affordable = (
    prices.length > 1
    and prices.keep(predicate: lambda (value: Int) -> Bool: return value <= 10).length > 0
)
