# conform: tags=formatter,lists,modules,optional,parser,stdlib-bytes,stdlib-http,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/http_header_test.go:11 TestHTTPRequestHeaderNavigation
from "@std/http.ms" import HttpRequest
from "@std/bytes.ms" import Bytes

def content_type(request: HttpRequest) -> Optional[List[Bytes]]:
    return request.headers.values_bytes("content-type")
