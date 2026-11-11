// conform: tags=diagnostics,match,optional,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:214 TestFormatExpressionLayouts
fn work(early: Int) Int:
	result := subtract(
		match 0:
			_value:
				10
			none: 10
	?
	)
	return result
