// conform: tags=diagnostics,lists,modules,optional,stdlib-bytes,stdlib-http,tier-io
// conform: phase=check
// conform: origin=pkg/tooling/lsp/http_header_test.go:11 TestHTTPRequestHeaderNavigation
import (
	Bytes from "@std/bytes.ms",
	HttpRequest from "@std/net/http.ms",
)

fn content_type(request HttpRequest) List[Bytes]? {
	return request.headers.get_all_bytes("content-type")
}
