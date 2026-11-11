// conform: tags=diagnostics
// conform: phase=check
fn work() Unit:
    send(payload: incoming_request_payload.normalize_whitespace().remove_legacy_separators().trim_whitespace())
