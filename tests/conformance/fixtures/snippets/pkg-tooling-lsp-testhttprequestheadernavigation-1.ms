# conform: tags=diagnostics,lists,modules,optional,stdlib-bytes,stdlib-http,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/lsp/http_header_test.go:11 TestHTTPRequestHeaderNavigation
from "@std/http.ms" import HttpRequest
from "@std/bytes.ms" import Bytes

def content_type(request: HttpRequest) -> Optional[List[Bytes]]:
    return request.headers.values("content-type")
