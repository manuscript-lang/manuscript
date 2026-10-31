# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:70 TestFormatExpressionLayouts
fn work() Unit:
    send_message(
        condition: account_is_active and payment_is_allowed and remaining_balance > 0
    )
