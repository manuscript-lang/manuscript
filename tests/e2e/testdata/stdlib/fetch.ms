from "@std/testing.ms" import expect_equal
from "@std/fetch.ms" import FetchBody, FetchOptions, FetcherOptions, check_status, read_json, fetch, fetcher, json_body
from "@std/http.ms" import HttpError, HttpHeaders, HttpMethod, HttpRequest, HttpResponse, headers
from "@std/net.ms" import network

type Greeting:
    name: String

def no_types(cause: HttpError) -> Optional[List[String]]:
    return none

def route(request: HttpRequest) -> HttpResponse:
    if request.path == "/missing":
        return HttpResponse(status: 404, headers: headers(), body: "nope".to_bytes())

    if request.path == "/old":
        var moved = headers()
        try_append(moved, "Location", "/echo")
        return HttpResponse(status: 302, headers: moved, body: "".to_bytes())

    if request.path == "/big":
        return HttpResponse(
            status: 200, headers: headers(), body: "0123456789".to_bytes()
        )

    let kind = request.headers.text("Content-Type").get_or_else(no_types)
    var label = ""
    if let values = kind:
        label = values[0].clone()
    return HttpResponse(
        status: 200,
        headers: headers(),
        body: f"{request.method.text()}|{label}|".to_bytes().concat(
            request.body.clone()
        )
    )

def try_append(fields: HttpHeaders, name: String, value: String) -> Unit:
    let _ignored = fields.append(name, value.to_bytes())

test "fetch returns a buffered text response":
    with let server = try network().serve("127.0.0.1:0", route):
        let response = try fetch(f"http://{server.address()}/echo")
        try expect_equal(response.ok(), True)
        try expect_equal(try response.text(), "GET||")

test "fetch posts text and JSON bodies with default content types":
    with let server = try network().serve("127.0.0.1:0", route):
        let url = f"http://{server.address()}/echo"
        let text = try fetch(
            url,
            some(
                FetchOptions(
                    method: HttpMethod.Post, body: FetchBody.Text("hi")
                )
            )
        )
        try expect_equal(try text.text(), "POST|text/plain; charset=utf-8|hi")

        let body = try json_body(Greeting(name: "ada"))
        let sent = try fetch(
            url, some(FetchOptions(method: HttpMethod.Post, body: body))
        )
        try expect_equal(
            try sent.text(), "POST|application/json|" + "{\"name\":\"ada\"}"
        )

test "fetch decodes JSON":
    with let server = try network().serve("127.0.0.1:0", json_route):
        let response = try fetch(f"http://{server.address()}/")
        let greeting = try read_json[Greeting](response)
        try expect_equal(greeting.name, "ada")

def json_route(request: HttpRequest) -> HttpResponse:
    return HttpResponse(
        status: 200, headers: headers(), body: "{\"name\":\"ada\"}".to_bytes()
    )

test "fetch follows redirects unless max_redirects is 0":
    with let server = try network().serve("127.0.0.1:0", route):
        let url = f"http://{server.address()}/old"
        let followed = try fetch(url)
        try expect_equal(followed.head.status, 200)

        with let client = try fetcher(FetcherOptions(max_redirects: some(0))):
            let stopped = try client.fetch(url)
            try expect_equal(stopped.head.status, 302)

test "error statuses are ordinary responses and check_status rejects them":
    with let server = try network().serve("127.0.0.1:0", route):
        let response = try fetch(f"http://{server.address()}/missing")
        try expect_equal(response.ok(), False)
        try expect_equal(check_status(response).is_error(), True)

test "fetch enforces max_response_bytes":
    with let server = try network().serve("127.0.0.1:0", route):
        let url = f"http://{server.address()}/big"
        let small = fetch(url, some(FetchOptions(max_response_bytes: some(4))))
        try expect_equal(small.is_error(), True)

        let whole = try fetch(url, some(FetchOptions(max_response_bytes: some(10))))
        try expect_equal(whole.body.length(), 10)
