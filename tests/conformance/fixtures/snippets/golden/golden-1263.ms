// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	HttpRequest from "@std/net/http.ms",
)

fn content_type(request HttpRequest) List[Bytes]? {
	return request.headers.get_all_bytes("content-type")
}
// expect-exit: 0
