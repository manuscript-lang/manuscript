// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	send(
		destination: destination_address,
		payload: encoded_message_payload,
		timeout: configured_request_timeout,
	)
}
