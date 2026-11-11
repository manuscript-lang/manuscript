// conform: tags=diagnostics
// conform: phase=check
fn work() Unit:
    values := [initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total, 0]
