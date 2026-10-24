# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:93 TestFormatExpressionLayouts
def work(
    balance: Int = initial_account_balance
    + pending_deposit_total * applicable_exchange_rate
    - pending_withdrawal_total
) -> Int:
    return balance
