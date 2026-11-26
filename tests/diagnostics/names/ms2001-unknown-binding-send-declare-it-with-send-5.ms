// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send(  // Delivery settings.
		first: 1,  // First setting.
		// Second setting.
		second: 2,
	)  // Completed settings.
}
// expect-error: MS2001 4:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
