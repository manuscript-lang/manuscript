// conform: tags=diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/http_header_test.go:23 TestLocalHttpHeadersDoesNotAcquireNativeLookup
type HttpHeaders {
	value String
}

fn lookup(fields HttpHeaders) Void {
	fields.values("content-type")
}
// expect-error: MS2001 9:12 unknown or ambiguous member values on HttpHeaders; did you mean 'value'?; available: value
