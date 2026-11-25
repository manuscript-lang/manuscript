// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send(
		payload: incoming_request_payload
		.normalize_whitespace()
		.remove_legacy_separators()
		.trim_whitespace()
	)
}
// expect-error: MS2001 4:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
