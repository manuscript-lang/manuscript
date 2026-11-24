// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send(
		destination: resolve(name: service, region: region),
		payload: encode(build(records)),
	)
}
