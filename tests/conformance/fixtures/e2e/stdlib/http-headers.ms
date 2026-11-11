// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	HttpClient,
	HttpClientOptions,
	HttpExchange,
	HttpHeaders,
	HttpMethod,
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	buffered,
	headers from "@std/net/http.ms",
	RequestOptions, http_client, request, serve from "@std/net/net.ms",
	expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test/test.ms",

	read_to_end, recv, send, send_bytes from "./support/conn.ms",
)

fn repeated_headers() HttpHeaders!:
	var fields = headers()
	_first := fields.append("x-dup", "first") | expect_ok?
	_second := fields.append("X-Dup", "second") | expect_ok?
	_cookie := (
		fields.append(
			"Set-Cookie",
			"a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT",
		)
		| expect_ok?
	)
	_other := fields.append("set-cookie", "b=2") | expect_ok?
	return ok(fields)

fn header_failure(message: String) HttpResponse:
	return HttpResponse(status: 500, headers: headers(), body: message.to_bytes())

fn handle_headers(request: HttpRequest) HttpResponse:
	if request.method != HttpMethod.Get: return header_failure("typed request method")

	received := request.headers.values("X-DUP")
	if received != ["first", "second"]: return header_failure(
		"case-insensitive received fields"
	)

	var fields = match repeated_headers():
		ok(found): found
		error(cause): return header_failure(cause.message)

	return HttpResponse(status: 200, headers: fields, body: "ok".to_bytes())

test "one header type preserves repeated values through buffered requests":
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: buffered(handle_headers),
			options: HttpServerOptions(max_requests: 2),
		) | expect_ok?
	)
	response := (
		request(
			method: HttpMethod.Get,
			url: "http://{server.address()}/",
			options: RequestOptions(headers: (repeated_headers()?)),
		) | expect_ok?
	)
	var metadata = response.metadata().clone()
	metadata.status | expect_equal(200)?
	metadata.headers.values("x-dup") | expect_equal(["first", "second"])?
	expect_false(
		(
			(metadata.headers.values("SET-COOKIE")) != [
				"a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT", "b=2"
			]
		)
	)?

	// The clone is independent: appending to it leaves the response's headers as
	// received.
	_appended := ((metadata.headers.append("x-dup", "third")) | expect_ok?)
	metadata.headers.values("X-Dup") | expect_equal(["first", "second", "third"])?
	expect_false(((response.metadata().headers.values("X-Dup")) != ["first", "second"]))?

fn echo_headers(var exchange: HttpExchange) Unit!:
	received := exchange.headers()
	if received.values("X-DUP") != ["first", "second"]: return error(
		Error("HTTP: invalid data", kind: "EBADMSG")
	)

	var output = received.clone()
	_removed_connection := output.remove("Connection")
	_removed_length := output.remove("Content-Length")
	return exchange.send_headers(status: 200, headers: output)

test "streaming proxy uses the same byte-valued header type":
	server := (
		serve(
			address: "127.0.0.1:0",
			handler: echo_headers,
			options: HttpServerOptions(tls: none),
		) | expect_ok?
	)
	response := (
		request(
			method: HttpMethod.Get,
			url: "http://{server.address()}/",
			options: RequestOptions(headers: (repeated_headers()?)),
		) | expect_ok?
	)
	expect_false(((response.metadata().headers.values("x-DUP")) != ["first", "second"]))?

test "lookup returns membership and clone separates it":
	var fields = (repeated_headers()?)
	_appended := fields.append("x-dup", "third") | expect_ok?
	values := fields.values("X-DUP")
	values.length() | expect_equal(3)?

	var copy = fields.clone()
	_copy_appended := copy.append("x-dup", "copy") | expect_ok?
	fields.values("x-dup").length() | expect_equal(3)?
	(not fields.contains("missing")) | expect_true?

	_k := fields.append("K", "ASCII") | expect_ok?
	(not fields.contains("K")) | expect_true?

	_removed := fields.remove("X-DUP")
	_new_field := fields.append("X-Dup", "new") | expect_ok?
	(fields.values("x-dup").length() != 1) | expect_false?

test "string lookup leaves out values that are not UTF-8":
	var fields = headers()
	_valid := fields.append("Raw", "first") | expect_ok?
	_invalid := fields.append_bytes("raw", Bytes(values: [255])) | expect_ok?
	fields.values("RAW") | expect_equal(["first"])?
	fields.values_bytes("RAW").get().length() | expect_equal(2)?

	match fields.append("bad name", "value"):
		ok(_): return fail("malformed name accepted")
		error(cause):
			expect_equal(cause, Error("HTTP: invalid input", kind: "EINVAL"))?

test "empty options and an omitted request body use checked defaults":
	client_options := HttpClientOptions()
	(client_options.decompress or client_options.cookies) | expect_false?
	(HttpServerOptions().tls.is_none()) | expect_true?

	server := (
		serve(
			address: "127.0.0.1:0",
			handler: echo_headers,
			options: HttpServerOptions(),
		) | expect_ok?
	)
	client := http_client(options: HttpClientOptions()) | expect_ok?
	response := (
		client.request(
			method: HttpMethod.Get,
			url: "http://{server.address()}/",
			headers: (repeated_headers()?),
		)
		| expect_ok?
	)
	response.metadata.status | expect_equal(200)?

fn cookie_handler(var exchange: HttpExchange) Unit!:
	var fields = headers()

	if exchange.path() == "/set":
		_added := fields.append(
			"Set-Cookie",
			"a=live; Path=/; Expires=Fri Jan  1 00:00:00 2100",
		)?
	else if exchange.path() == "/rfc850":
		_added := fields.append(
			"Set-Cookie",
			"a=gone; Path=/; Expires=Thursday, 01-Jan-70 00:00:01 GMT",
		)?
	else if exchange.path() == "/asctime":
		_added := fields.append(
			"Set-Cookie",
			"a=gone; Path=/; Expires=Thu Jan  1 00:00:01 1970",
		)?

	cookie := exchange.headers().values("Cookie").join("; ")
	return exchange.send(200, fields, cookie.to_bytes())

fn echoed_cookie(client: HttpClient, url: String) String!:
	var response = client.request(HttpMethod.Get, url, headers(), timeout: 3.seconds())?
	var text = ""
	for chunk in response.body:
		text += chunk.decode_utf8().get()
	response.close()?
	return ok(text)

test "legacy Expires removes a cookie before the next request":
	server := serve(
		"127.0.0.1:0",
		cookie_handler,
		HttpServerOptions(timeout: 3.seconds()),
	)?
	client := http_client(HttpClientOptions(cookies: true))?
	url := "http://{server.address()}"

	for path in ["/rfc850", "/asctime"]:
		_set := echoed_cookie(client, "{url}/set")?
		(echoed_cookie(client, "{url}{path}")?) | expect_equal("a=live")?
		(echoed_cookie(client, "{url}/echo")?) | expect_equal("")?
