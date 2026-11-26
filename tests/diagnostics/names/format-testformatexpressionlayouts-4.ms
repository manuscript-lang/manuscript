// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:70 TestFormatExpressionLayouts
fn work() Void {
	send_message(
		condition: account_is_active and payment_is_allowed and remaining_balance > 0
	)
}
// expect-error: MS2001 5:5 unknown binding send_message; declare it with 'send_message := ...' before use, define 'fn send_message(...) T { ... }', or import it from a module
