// conform: tags=diagnostics
// conform: phase=check
fn work() String {
	return incoming_request_payload.normalize_whitespace().replace(
		old: legacy_separator,
		new: current_separator,
	).trim()
}
// expect-error: MS2001 4:12 unknown binding incoming_request_payload; declare it with 'incoming_request_payload := ...' before use, define 'fn incoming_request_payload(...) T { ... }', or import it from a module
// expect-error: MS2001 5:14 unknown binding legacy_separator; declare it with 'legacy_separator := ...' before use, define 'fn legacy_separator(...) T { ... }', or import it from a module
// expect-error: MS2001 6:14 unknown binding current_separator; declare it with 'current_separator := ...' before use, define 'fn current_separator(...) T { ... }', or import it from a module
