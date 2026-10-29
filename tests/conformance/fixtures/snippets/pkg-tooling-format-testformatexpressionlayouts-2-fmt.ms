# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:56 TestFormatExpressionLayouts
fn work() Unit:
    try expect_false(
        try parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options) != [
            ["line\n\nbreak"], [""]
        ]
    )
