# conform: tags=diagnostics,lists,modules,optional,stdlib-bytes,stdlib-http,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/lsp/http_header_test.go:11 TestHTTPRequestHeaderNavigation
import HttpRequest from "@std/http.ms"
import Bytes from "@std/bytes.ms"

fn content_type(request: HttpRequest) Optional[List[Bytes]]:
    return request.headers.values("content-type")
