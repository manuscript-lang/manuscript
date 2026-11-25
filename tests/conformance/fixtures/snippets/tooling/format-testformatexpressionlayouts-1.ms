// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:53 TestFormatExpressionLayouts
fn work() Void {
	expect_false(
		parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options)? != [
			["line\n\nbreak"],
			[""],
		]
	)?
}
// expect-error: MS2001 5:5 unknown binding expect_false; add: import expect_false from "@std/test/test.ms"
// expect-fix: 1:1-1:1 "import expect_false from \"@std/test/test.ms\"\n"
