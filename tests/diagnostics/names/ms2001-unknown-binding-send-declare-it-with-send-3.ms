// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send(
		destination: resolve(name: service, region: region),
		payload: encode(build(records)),
	)
}
// expect-error: MS2001 4:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
