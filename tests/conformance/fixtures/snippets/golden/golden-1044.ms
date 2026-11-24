// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send_message(
		condition: account_is_active and payment_is_allowed and remaining_balance > 0
	)
}
