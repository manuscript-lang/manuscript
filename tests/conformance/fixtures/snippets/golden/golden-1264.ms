// conform: tags=diagnostics
// conform: phase=check
type HttpHeaders:
    value String
fn lookup(fields HttpHeaders) Void:
    fields.values("content-type")
