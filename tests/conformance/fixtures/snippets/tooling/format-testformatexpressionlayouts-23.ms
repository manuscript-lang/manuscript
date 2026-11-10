// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:197 TestFormatExpressionLayouts
prices := [12, 8, 25]
affordable := (
    prices.length > 1
    and prices.keep(predicate: fn(value: Int) Bool: return value <= 10).length > 0
)
