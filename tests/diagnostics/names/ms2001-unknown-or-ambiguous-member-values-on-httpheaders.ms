// conform: tags=diagnostics
// conform: phase=check
type HttpHeaders {
	value String
}

fn lookup(fields HttpHeaders) Void {
	fields.values("content-type")
}
// expect-error: MS2001 8:12 unknown or ambiguous member values on HttpHeaders; did you mean 'value'?; available: value
