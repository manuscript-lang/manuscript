// conform: tags=testing,tier-io
// conform: phase=test
import (
	HttpExchange,
	HttpMethod,
	HttpRequest,
	HttpResponse,
	buffered,
	headers from "@std/net/http.ms",
	RequestOptions, request, serve from "@std/net/net.ms",
	expect_ok from "@std/test/test.ms",
)

fn echo(request: HttpRequest) HttpResponse:
	return HttpResponse(status: 200, headers: headers(), body: request.path.to_bytes())

// A handler that answers one route itself and hands every other request to a buffered
// handler it captured: the closure calls another closure with its `var` exchange.
fn routed() fn(var HttpExchange) Unit!:
	inner := buffered(echo)

	return fn(var exchange: HttpExchange) Unit!:
		if exchange.path() == "/health": return exchange.send(200, headers(), "ok".to_bytes())
		return inner(var exchange)

fn get(url: String) String!:
	response := request(method: HttpMethod.Get, url: url) | expect_ok?
	if text := response.body.decode_utf8(): return ok(text)
	return error(Error("body is not UTF-8"))

test "a handler can wrap a buffered handler it captured":
	server := serve(address: "127.0.0.1:0", handler: routed()) | expect_ok?
	base := "http://{server.address()}"

	own := get("{base}/health")?
	if own != "ok": return error(Error("own route: {own}"))
	if get("{base}/x/y")? != "/x/y": return error(Error("delegated route"))
