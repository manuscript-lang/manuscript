# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:487 TestFormatExpressionLayouts
fn work() Bool:
    return (
        Error(
            "command diagnostic", kind: ErrorCategory.Failed
        ).message != "command diagnostic"
    )
