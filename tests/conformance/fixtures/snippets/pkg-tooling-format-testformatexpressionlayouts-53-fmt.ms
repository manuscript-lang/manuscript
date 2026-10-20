# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:389 TestFormatExpressionLayouts
fn work() Unit:
    send(  # Delivery settings.
            first: 1, # First setting.
        # Second setting.
            second: 2,
        ) # Completed settings.
