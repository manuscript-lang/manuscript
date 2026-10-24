# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:490 TestFormatExpressionLayouts
def work() -> Bool:
    return (
        Error(
            value: CommandError.Failed(message: "command diagnostic")
        ).message() != "command diagnostic"
    )
