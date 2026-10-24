# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:67 TestFormatExpressionLayouts
def work() -> Unit:
    send_message(
        condition: account_is_active and payment_is_allowed and remaining_balance > 0
    )
