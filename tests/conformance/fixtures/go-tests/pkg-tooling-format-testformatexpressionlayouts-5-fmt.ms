# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:78 TestFormatExpressionLayouts
fn work() Unit:
    send(condition: account_is_active or payment_is_allowed and remaining_balance > minimum_balance)
