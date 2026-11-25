// conform: tags=testing,tier-io
// conform: phase=test
import (
	HttpExchange,
	HttpMethod,
	HttpRequest,
	HttpResponse,
	buffered,
	headers,
	read_body,
	reply,
	text from "@std/net/http.ms",
	http_client, serve from "@std/net/net.ms",
	expect_equal from "@std/test/test.ms",
)

fn echo(request HttpRequest) HttpResponse {
	return text(201, f"{request.path}:{(request.body.decode_utf8() or "")}")
}

fn exchange_echo(var exchange HttpExchange) Void! {
	body := read_body(exchange, 8)?
	return reply(exchange, text(200, f"{body.length()}"))
}

test "buffered adapts a request-to-response handler" {
	server := serve("127.0.0.1:0", buffered(echo))?
	client := http_client()?
	var response = client.request(
		HttpMethod.Post,
		f"http://{server.address()}/x",
		headers(),
		"abc",
	)?
	expect_equal(response.metadata.status, 201)?

	var text = ""
	for chunk in response.body {
		text += chunk.decode_utf8() or ""
	}
	expect_equal(text, "/x:abc")?
}

test "read_body bounds the body by its limit" {
	server := serve("127.0.0.1:0", exchange_echo)?
	client := http_client()?
	small := client.request(
		HttpMethod.Post,
		f"http://{server.address()}/",
		headers(),
		"12345",
	)?
	expect_equal(small.metadata.status, 200)?

	large := client.request(
		HttpMethod.Post,
		f"http://{server.address()}/",
		headers(),
		"123456789",
	)?
	expect_equal(large.metadata.status, 500)?
}

fn bare(request HttpRequest) HttpResponse {
	return HttpResponse(status: 200, body: "bare".to_bytes())
}

test "serve, the client and a response take their defaults" {
	server := serve("127.0.0.1:0", buffered(bare))?
	client := http_client()?
	var response = client.request(HttpMethod.Get, f"http://{server.address()}/")?
	expect_equal(response.metadata.status, 200)?

	var got = ""
	for chunk in response.body {
		got += chunk.decode_utf8() or ""
	}
	expect_equal(got, "bare")?
}
