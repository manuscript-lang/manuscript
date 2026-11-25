// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:309 TestFormatExpressionLayouts
fn work() Void {
	send(condition: active and allowed and remaining > 0, payload: "data")
}
// expect-error: MS2001 5:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
