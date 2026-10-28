# conform: tags=formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/http_header_test.go:23 TestLocalHttpHeadersDoesNotAcquireNativeLookup
type HttpHeaders:
    value: String

fn lookup(fields: HttpHeaders) Unit:
    fields.values("content-type")
