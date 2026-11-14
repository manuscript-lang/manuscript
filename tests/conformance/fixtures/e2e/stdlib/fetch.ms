// conform: tags=testing,tier-io
// conform: phase=test
import (
	FetchBody,
	FetchOptions,
	FetcherOptions,
	fetch,
	fetcher,
	json_body from "@std/net/fetch.ms",
	HttpHeaders,
	HttpMethod,
	HttpRequest,
	HttpResponse,
	buffered,
	headers from "@std/net/http.ms",
	serve from "@std/net/net.ms",
	expect_equal from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",

	read_to_end from "./support/conn.ms",
)

type Greeting:
	name: String

fn route(request: HttpRequest) HttpResponse:
	if request.path == "/missing":
		return HttpResponse(status: 404, headers: headers(), body: "nope".to_bytes())

	if request.path == "/old":
		var moved = headers()
		try_append(var moved, "Location", "/echo")
		return HttpResponse(status: 302, headers: moved, body: "".to_bytes())

	if request.path == "/chain":
		var moved = headers()
		try_append(var moved, "Location", "/preserve")
		return HttpResponse(status: 302, headers: moved, body: "".to_bytes())

	if request.path == "/preserve":
		var moved = headers()
		try_append(var moved, "Location", "/echo")
		return HttpResponse(status: 307, headers: moved, body: "".to_bytes())

	if request.path == "/slow":
		_ := sleep(milliseconds(1500)).wait()
		return HttpResponse(status: 200, headers: headers(), body: "late".to_bytes())

	if request.path == "/big":
		return HttpResponse(
			status: 200,
			headers: headers(),
			body: "0123456789".to_bytes(),
		)

	label := request.headers.values("Content-Type").first().get("")
	return HttpResponse(
		status: 200,
		headers: headers(),
		body: "{request.method.text()}|{label}|".to_bytes().concat(
			request.body.clone()
		),
	)

fn try_append(var fields: HttpHeaders, name: String, value: String) Unit:
	_ignored := fields.append(name, value)

test "fetch returns a buffered text response":
	server := serve("127.0.0.1:0", buffered(route))?
	response := fetch("http://{server.address()}/echo").wait()?
	expect_equal(response.ok(), true)?
	expect_equal(response.text()?, "GET||")?

test "fetch posts text and JSON bodies with default content types":
	server := serve("127.0.0.1:0", buffered(route))?
	url := "http://{server.address()}/echo"
	text := fetch(
		url,
		FetchOptions(method: HttpMethod.Post, body: FetchBody.Text("hi")),
	).wait()?
	expect_equal(text.text()?, "POST|text/plain; charset=utf-8|hi")?

	body := json_body(Greeting(name: "ada"))?
	sent := fetch(url, FetchOptions(method: HttpMethod.Post, body: body)).wait()?
	expect_equal(sent.text()?, "POST|application/json|" + "\{\"name\":\"ada\"\}")?

test "fetch decodes JSON":
	server := serve("127.0.0.1:0", buffered(json_route))?
	response := fetch("http://{server.address()}/").wait()?
	greeting := response.json[Greeting]()?
	expect_equal(greeting.name, "ada")?

fn json_route(request: HttpRequest) HttpResponse:
	return HttpResponse(
		status: 200,
		headers: headers(),
		body: "\{\"name\":\"ada\"\}".to_bytes(),
	)

test "fetch follows redirects unless max_redirects is 0":
	server := serve("127.0.0.1:0", buffered(route))?
	url := "http://{server.address()}/old"
	followed := fetch(url).wait()?
	expect_equal(followed.head.status, 200)?

	client := fetcher(FetcherOptions(max_redirects: 0))?
	stopped := client.fetch(url).wait()?
	expect_equal(stopped.head.status, 302)?

test "fetch does not restore Content-Type after a redirect drops its body":
	server := serve("127.0.0.1:0", buffered(route))?
	response := fetch(
		"http://{server.address()}/chain",
		FetchOptions(method: HttpMethod.Post, body: FetchBody.Text("hello")),
	).wait()?
	expect_equal(response.head.status, 200)?
	expect_equal(response.text()?, "GET||")?

test "error statuses are ordinary responses and check_status rejects them":
	server := serve("127.0.0.1:0", buffered(route))?
	response := fetch("http://{server.address()}/missing").wait()?
	expect_equal(response.ok(), false)?
	expect_equal(response.check_status().is_error(), true)?

test "fetch enforces max_response_bytes":
	server := serve("127.0.0.1:0", buffered(route))?
	url := "http://{server.address()}/big"
	small := fetch(url, FetchOptions(max_response_bytes: 4)).wait()
	expect_equal(small.is_error(), true)?
	expect_equal(small.err().kind, "EOVERFLOW")?

	whole := fetch(url, FetchOptions(max_response_bytes: 10)).wait()?
	expect_equal(whole.body.length(), 10)?

test "fetch times out a slow response":
	server := serve("127.0.0.1:0", buffered(route))?
	url := "http://{server.address()}/slow"
	slow := fetch(url, FetchOptions(timeout: milliseconds(200))).wait()
	expect_equal(slow.is_error(), true)?
	expect_equal(slow.err().message, "HTTP: operation timed out")?

test "Fetcher.stream returns the body incrementally and reuses the client":
	server := serve("127.0.0.1:0", buffered(route))?
	client := fetcher()?
	url := "http://{server.address()}/big"
	var response = client.stream(url)?
	expect_equal(read_to_end(var response.body)?, "0123456789".to_bytes())?
	expect_equal(response.metadata.status, 200)?
	response.body.close()?

	again := client.fetch(url).wait()?
	expect_equal(again.body.length(), 10)?

test "a closed Fetcher returns Closed":
	server := serve("127.0.0.1:0", buffered(route))?
	var client = fetcher()?
	client.close()?

	sent := client.fetch("http://{server.address()}/big")
	expect_equal(sent.wait().err().message, "HTTP: resource is closed")?
