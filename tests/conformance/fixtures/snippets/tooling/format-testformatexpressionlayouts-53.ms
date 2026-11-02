# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:389 TestFormatExpressionLayouts
fn work() Unit:
    send(  # Delivery settings.
        first: 1,  # First setting.
        # Second setting.
        second: 2,
    )  # Completed settings.
