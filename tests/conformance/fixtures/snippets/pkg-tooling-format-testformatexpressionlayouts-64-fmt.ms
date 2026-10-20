# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:458 TestFormatExpressionLayouts
fn work() Unit:
    let values = [
        initial_account_balance
        + pending_deposit_total * applicable_exchange_rate
        - pending_withdrawal_total,
        0
    ]
