# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:56 TestFormatExpressionLayouts
def work() -> Unit:
    try expect_false(
        try parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options) != [
            ["line\n\nbreak"], [""]
        ]
    )
