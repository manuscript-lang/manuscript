// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send(
		destination: destination_address,
		payload: encoded_message_payload,
		timeout: configured_request_timeout,
	)
}
// expect-error: MS2001 4:5 unknown binding send; declare it with 'send := ...' before use, define 'fn send(...) T { ... }', or import it from a module
