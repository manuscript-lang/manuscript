// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:197 TestFormatExpressionLayouts
prices := [12, 8, 25]
affordable := (
	prices.length > 1
	and prices.keep(predicate: fn(value Int) Bool => return value <= 10).length > 0
)
// expect-error: MS3070 6:12 a constant takes literals, operators, collections, and other constants; compute this value in a function
