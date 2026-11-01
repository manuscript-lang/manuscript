# conform: tags=formatter,lists,modules,optional,parser,stdlib-bytes,stdlib-http,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/http_header_test.go:11 TestHTTPRequestHeaderNavigation
import HttpRequest from "@std/net/http.ms"
import Bytes from "@std/bytes.ms"

fn content_type(request: HttpRequest) List[Bytes]?:
    return request.headers.values_bytes("content-type")
