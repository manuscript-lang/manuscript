# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:487 TestFormatExpressionLayouts
fn work() Bool:
    return (
        Error(
            "command diagnostic", kind: ErrorCategory.Failed
        ).message != "command diagnostic"
    )
