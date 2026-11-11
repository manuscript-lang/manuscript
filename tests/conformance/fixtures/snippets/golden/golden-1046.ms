// conform: tags=diagnostics
// conform: phase=check
fn work() Unit:
    send(condition: account_is_active or payment_is_allowed and remaining_balance > minimum_balance)
