# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:340 TestFormatExpressionLayouts
fn work() Int:
    return initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total
