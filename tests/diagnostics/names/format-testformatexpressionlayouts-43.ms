// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:327 TestFormatExpressionLayouts
fn work() Bool {
	return (
		account_is_active
		and payment_is_allowed
		and remaining_balance > minimum_balance
	)
}
// expect-error: MS2001 6:9 unknown binding account_is_active; declare it with 'account_is_active := ...' before use, define 'fn account_is_active(...) T { ... }', or import it from a module
// expect-error: MS2001 7:13 unknown binding payment_is_allowed; declare it with 'payment_is_allowed := ...' before use, define 'fn payment_is_allowed(...) T { ... }', or import it from a module
// expect-error: MS2001 8:13 unknown binding remaining_balance; declare it with 'remaining_balance := ...' before use, define 'fn remaining_balance(...) T { ... }', or import it from a module
// expect-error: MS2001 8:33 unknown binding minimum_balance; declare it with 'minimum_balance := ...' before use, define 'fn minimum_balance(...) T { ... }', or import it from a module
