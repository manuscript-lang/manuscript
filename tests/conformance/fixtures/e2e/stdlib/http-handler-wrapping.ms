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
fn routed() fn(var HttpExchange) Void!:
	inner := buffered(echo)

	return fn(var exchange: HttpExchange) Void!:
		if exchange.path() == "/health": return exchange.send(
			200,
			headers(),
			"ok".to_bytes(),
		)
		return inner(exchange)

fn get(url: String) String!:
	response := request(method: HttpMethod.Get, url: url) | expect_ok?
	text := response.body.decode_utf8()
	if text != null: return ok(text)

	return error(Error("body is not UTF-8"))

test "a handler can wrap a buffered handler it captured":
	server := serve(address: "127.0.0.1:0", handler: routed()) | expect_ok?
	base := f"http://{server.address()}"
	own := get(f"{base}/health")?
	if own != "ok": return error(Error(f"own route: {own}"))
	if get(f"{base}/x/y")? != "/x/y": return error(Error("delegated route"))
