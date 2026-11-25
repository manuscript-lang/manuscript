// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:238 TestFormatExpressionLayouts
fn work() Void {
	send(
		destination: resolve(name: service, region: region),
		payload: encode(build(records)),
	)
}
// expect-error: MS2001 5:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
