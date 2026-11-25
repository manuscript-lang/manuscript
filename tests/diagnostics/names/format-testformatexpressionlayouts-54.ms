// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:396 TestFormatExpressionLayouts
fn work() Void {
	send(  // Delivery settings.
		first: 1,  // First setting.
		// Second setting.
		second: 2,
	)  // Completed settings.
}
// expect-error: MS2001 5:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
