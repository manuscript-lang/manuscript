// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:78 TestFormatExpressionLayouts
fn work() Void {
	send(
		condition: account_is_active
		or payment_is_allowed and remaining_balance > minimum_balance
	)
}
// expect-error: MS2001 5:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
