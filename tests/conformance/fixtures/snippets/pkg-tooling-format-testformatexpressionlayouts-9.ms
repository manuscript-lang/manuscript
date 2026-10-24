# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:103 TestFormatExpressionLayouts
def work() -> Unit:
    let values = {
        "balance": initial_account_balance
        + pending_deposit_total * applicable_exchange_rate
        - pending_withdrawal_total
    }
