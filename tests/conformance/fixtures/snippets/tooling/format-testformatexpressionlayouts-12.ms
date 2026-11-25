// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:119 TestFormatExpressionLayouts
fn work() Void {
	send(
		payload: incoming_request_payload
		.normalize_whitespace()
		.remove_legacy_separators()
		.trim_whitespace()
	)
}
// expect-error: MS2001 5:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
