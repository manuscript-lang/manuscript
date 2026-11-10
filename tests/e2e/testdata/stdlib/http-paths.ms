import (
	expect_ok from "@std/test/test.ms",
	http_result from "./support/http.ms",
	headers, HttpMethod, buffered from "@std/net/http.ms",
	text_headers, list_headers from "./support/http.ms",
	HttpRequest,
	HttpResponse,
	HttpExchange,
	HttpServerOptions,
	HttpClientOptions,
	HttpHeaders from "@std/net/http.ms",
	RequestOptions, http_client, request, serve from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	Bytes from "@std/bytes.ms",
)

fn route(request: HttpRequest) HttpResponse:
	var cookies = Map[String, String]()
	cookies.add("Set-Cookie", "a=1")
	cookies.add("set-cookie", "b=2")

	fields := match text_headers(cookies):
		ok(found): found
		error(cause): return HttpResponse(
			status: 500, headers: headers(), body: (cause.message.to_bytes())
		)

	return HttpResponse(
		status: 200, headers: fields, body: "{request.path}|{request.query}".to_bytes()
	)

fn stream_route(var exchange: HttpExchange) Unit!:
	var chain_1 = Map[String, List[String]]()
	chain_1.add(key: "Set-Cookie", value: ["a=1", "b=2"])

	_sent := try exchange.send_headers(
		status: 200, headers: (try list_headers(chain_1))
	)
	_written := (
		try http_result(exchange.write("{exchange.path()}|{exchange.query()}"))
	)

fn check_route(url: String, expected: String) Unit!:
	response := request(
		method: HttpMethod.Get,
		url: url,
		options: RequestOptions(
			headers: (try text_headers(Map[String, String]())), timeout: 2.seconds()
		)
	) | try expect_ok
	if response.metadata().status != 200 or response.body != expected.to_bytes(): return error(
		Error("path or raw query changed")
	)
	if ((response.metadata().headers.values("SET-cookie")) != ["a=1", "b=2"]): return error(
		Error("#257 repeated cookies regressed")
	)

fn check_rejected(url: String) Unit!:
	response := request(
		method: HttpMethod.Get,
		url: url,
		options: RequestOptions(
			headers: (try text_headers(Map[String, String]())), timeout: 2.seconds()
		)
	) | try expect_ok
	if response.metadata().status != 400: return error(
		Error("unsafe or invalid path was dispatched")
	)

fn check_paths(base: String) Unit!:
	(try check_route(url: "{base}/a%20b", expected: "/a b|"))
	(try check_route(url: "{base}/%2e%2e/x?y=%2F", expected: "/x|y=%2F"))
	(try check_route(url: "{base}/a/../b/", expected: "/b/|"))
	(try check_route(url: "{base}/a%252Fb?x=%2500", expected: "/a%2Fb|x=%2500"))
	(try check_rejected("{base}/a%2Fb"))
	(try check_rejected("{base}/a%00b"))
	(try check_rejected("{base}/bad%ff/../x"))

test "buffered routes validate original input and decode once":
	server := serve(address: "127.0.0.1:0", handler: buffered(route)) | try expect_ok
	(try check_paths("http://{server.address()}"))

test "streaming routes validate original input and decode once":
	server := serve(
		address: "127.0.0.1:0", handler: stream_route,
		options: HttpServerOptions(tls: none)
	) | try expect_ok
	(try check_paths("http://{server.address()}"))

fn expect_http_error[T](outcome: T!) Unit!:
	match outcome:
		ok(_): return error(Error("invalid URL succeeded"))
		error(cause):
			if cause.kind != "EINVAL": return error(
				Error("malformed URL leaked transport error")
			)

test "buffered and reusable clients reject malformed ports as InvalidInput":
	headers := (try text_headers(Map[String, String]()))
	body := ""
	request(
		method: HttpMethod.Get, url: "http://127.0.0.1:99999/", body: body,
		options: RequestOptions(headers: headers.clone())
	) | try expect_http_error

	tls := TlsOptions(
		server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
		alpn: [], require_client_certificate: false
	)
	client := http_client(
		HttpClientOptions(decompress: false, cookies: false, tls: tls)
	) | try expect_ok
	client.request(
		method: HttpMethod.Get, url: "http://127.0.0.1:65536/", headers: headers,
		body: body
	) | try expect_http_error

test "buffered and reusable clients reject URLs with an empty host":
	fields := headers()
	client := http_client(HttpClientOptions()) | try expect_ok

	for address in ["http://:80/", "https://:443/", "http://:/", "https://:/"]:
		request(HttpMethod.Get, address, options: RequestOptions(timeout: 1.seconds())) | try expect_http_error
		client.request(
			HttpMethod.Get, address, fields.clone(), timeout: 1.seconds()
		) | try expect_http_error
