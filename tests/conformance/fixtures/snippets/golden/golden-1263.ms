// conform: tags=diagnostics
// conform: phase=check
import HttpRequest from "@std/net/http.ms"
import Bytes from "@std/bytes.ms"
fn content_type(request: HttpRequest) List[Bytes]?:
    return request.headers.values_bytes("content-type")
