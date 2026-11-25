// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:260 TestFormatExpressionLayouts
fn work() Void {
	_larger := [1, 2, 3, 4, 5]
	_nested := [[1, 2], [3, 4]]
}
// expect-exit: 0
