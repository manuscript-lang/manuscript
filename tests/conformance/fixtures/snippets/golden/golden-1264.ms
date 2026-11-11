// conform: tags=diagnostics
// conform: phase=check
type HttpHeaders:
    value: String
fn lookup(fields: HttpHeaders) Unit:
    fields.values("content-type")
