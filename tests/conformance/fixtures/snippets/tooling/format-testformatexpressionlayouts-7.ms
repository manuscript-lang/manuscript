// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:90 TestFormatExpressionLayouts
fn work(
	balance Int = initial_account_balance
	+ pending_deposit_total * applicable_exchange_rate
	- pending_withdrawal_total
) Int {
	return balance
}
// expect-error: MS2001 5:19 unknown binding initial_account_balance; declare it with 'initial_account_balance := ...' before use, define 'fn initial_account_balance(...) T { ... }', or import it from a module
// expect-error: MS2001 6:7 unknown binding pending_deposit_total; declare it with 'pending_deposit_total := ...' before use, define 'fn pending_deposit_total(...) T { ... }', or import it from a module
// expect-error: MS2001 6:31 unknown binding applicable_exchange_rate; declare it with 'applicable_exchange_rate := ...' before use, define 'fn applicable_exchange_rate(...) T { ... }', or import it from a module
// expect-error: MS2001 7:7 unknown binding pending_withdrawal_total; declare it with 'pending_withdrawal_total := ...' before use, define 'fn pending_withdrawal_total(...) T { ... }', or import it from a module
