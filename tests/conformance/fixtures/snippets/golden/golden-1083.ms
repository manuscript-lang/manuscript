// conform: tags=diagnostics
// conform: phase=check
fn work() String:
    return incoming_request_payload.normalize_whitespace().replace(old: legacy_separator, new: current_separator).trim()
