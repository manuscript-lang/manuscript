# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:396 TestFormatExpressionLayouts
def work() -> Unit:
    send(  # Delivery settings.
        first: 1,  # First setting.
        # Second setting.
        second: 2,
    )  # Completed settings.
