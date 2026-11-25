// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	values := {
		"balance": initial_account_balance
		+ pending_deposit_total * applicable_exchange_rate
		- pending_withdrawal_total
	}
}
// expect-error: MS2001 5:20 unknown binding initial_account_balance; declare it with 'initial_account_balance := ...' before use, define 'fn initial_account_balance(...) T { ... }', or import it from a module
// expect-error: MS2001 6:11 unknown binding pending_deposit_total; declare it with 'pending_deposit_total := ...' before use, define 'fn pending_deposit_total(...) T { ... }', or import it from a module
// expect-error: MS2001 6:35 unknown binding applicable_exchange_rate; declare it with 'applicable_exchange_rate := ...' before use, define 'fn applicable_exchange_rate(...) T { ... }', or import it from a module
// expect-error: MS2001 7:11 unknown binding pending_withdrawal_total; declare it with 'pending_withdrawal_total := ...' before use, define 'fn pending_withdrawal_total(...) T { ... }', or import it from a module
