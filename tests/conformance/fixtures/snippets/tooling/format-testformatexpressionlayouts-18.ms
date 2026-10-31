# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:165 TestFormatExpressionLayouts
fn work() Unit:
    let _values = [
        1,  # Keep the first value explained.
        2,
        3,
        4
    ]
