# conform: tags=diagnostics,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/http_header_test.go:23 TestLocalHttpHeadersDoesNotAcquireNativeLookup
type HttpHeaders:
    value: String

def lookup(fields: HttpHeaders) -> Unit:
    fields.values("content-type")
