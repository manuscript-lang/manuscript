// conform: tags=formatter,parser,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/tooling/format/format_layout_test.go:53 TestFormatExpressionLayouts
fn work() Unit:
	expect_false(
		parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options)? != [
			["line\n\nbreak"], [""]
		]
	)?
