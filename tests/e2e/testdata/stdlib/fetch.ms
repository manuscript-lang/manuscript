import (
    read_to_end from "./support/conn.ms",
    expect_equal from "@std/test/test.ms",
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
    headers,
    buffered from "@std/net/http.ms",
    serve from "@std/net/net.ms",
    milliseconds, sleep from "@std/time.ms",
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
            status: 200, headers: headers(), body: "0123456789".to_bytes()
        )

    label := request.headers.values("Content-Type").first().get("")
    return HttpResponse(
        status: 200,
        headers: headers(),
        body: "{request.method.text()}|{label}|".to_bytes().concat(
            request.body.clone()
        )
    )

fn try_append(var fields: HttpHeaders, name: String, value: String) Unit:
    _ignored := fields.append(name, value)

test "fetch returns a buffered text response":
    server := try serve("127.0.0.1:0", buffered(route))
    response := try fetch("http://{server.address()}/echo").wait()
    try expect_equal(response.ok(), true)
    try expect_equal(try response.text(), "GET||")

test "fetch posts text and JSON bodies with default content types":
    server := try serve("127.0.0.1:0", buffered(route))
    url := "http://{server.address()}/echo"
    text := try fetch(
        url, FetchOptions(method: HttpMethod.Post, body: FetchBody.Text("hi"))
    ).wait()
    try expect_equal(try text.text(), "POST|text/plain; charset=utf-8|hi")

    body := try json_body(Greeting(name: "ada"))
    sent := try fetch(url, FetchOptions(method: HttpMethod.Post, body: body)).wait()
    try expect_equal(try sent.text(), "POST|application/json|" + "\{\"name\":\"ada\"\}")

test "fetch decodes JSON":
    server := try serve("127.0.0.1:0", buffered(json_route))
    response := try fetch("http://{server.address()}/").wait()
    greeting := try response.json[Greeting]()
    try expect_equal(greeting.name, "ada")

fn json_route(request: HttpRequest) HttpResponse:
    return HttpResponse(
        status: 200, headers: headers(), body: "\{\"name\":\"ada\"\}".to_bytes()
    )

test "fetch follows redirects unless max_redirects is 0":
    server := try serve("127.0.0.1:0", buffered(route))
    url := "http://{server.address()}/old"
    followed := try fetch(url).wait()
    try expect_equal(followed.head.status, 200)

    client := try fetcher(FetcherOptions(max_redirects: 0))
    stopped := try client.fetch(url).wait()
    try expect_equal(stopped.head.status, 302)

test "fetch does not restore Content-Type after a redirect drops its body":
    server := try serve("127.0.0.1:0", buffered(route))
    response := try fetch(
        "http://{server.address()}/chain",
        FetchOptions(method: HttpMethod.Post, body: FetchBody.Text("hello"))
    ).wait()
    try expect_equal(response.head.status, 200)
    try expect_equal(try response.text(), "GET||")

test "error statuses are ordinary responses and check_status rejects them":
    server := try serve("127.0.0.1:0", buffered(route))
    response := try fetch("http://{server.address()}/missing").wait()
    try expect_equal(response.ok(), false)
    try expect_equal(response.check_status().is_error(), true)

test "fetch enforces max_response_bytes":
    server := try serve("127.0.0.1:0", buffered(route))
    url := "http://{server.address()}/big"
    small := fetch(url, FetchOptions(max_response_bytes: 4)).wait()
    try expect_equal(small.is_error(), true)

    whole := try fetch(url, FetchOptions(max_response_bytes: 10)).wait()
    try expect_equal(whole.body.length(), 10)

test "fetch times out a slow response":
    server := try serve("127.0.0.1:0", buffered(route))
    url := "http://{server.address()}/slow"
    slow := fetch(url, FetchOptions(timeout: milliseconds(200))).wait()
    try expect_equal(slow.is_error(), true)
    try expect_equal(slow.err().message, "HTTP: operation timed out")

test "Fetcher.stream returns the body incrementally and reuses the client":
    server := try serve("127.0.0.1:0", buffered(route))
    client := try fetcher()
    url := "http://{server.address()}/big"
    var response = try client.stream(url)
    try expect_equal(try read_to_end(var response.body), "0123456789".to_bytes())
    try expect_equal(response.metadata.status, 200)
    try response.body.close()

    again := try client.fetch(url).wait()
    try expect_equal(again.body.length(), 10)

test "a closed Fetcher returns Closed":
    server := try serve("127.0.0.1:0", buffered(route))
    var client = try fetcher()
    try client.close()

    sent := client.fetch("http://{server.address()}/big")
    try expect_equal(sent.wait().err().message, "HTTP: resource is closed")
