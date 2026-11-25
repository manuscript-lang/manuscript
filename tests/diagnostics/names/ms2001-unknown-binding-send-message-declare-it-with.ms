// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send_message(
		condition: account_is_active and payment_is_allowed and remaining_balance > 0
	)
}
// expect-error: MS2001 4:5 unknown binding send_message; declare it with 'send_message := ...' before use, define 'fn send_message(...) T { ... }', or import it from a module
