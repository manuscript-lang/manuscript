// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send(
		condition: account_is_active
		or payment_is_allowed and remaining_balance > minimum_balance
	)
}
// expect-error: MS2001 4:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
