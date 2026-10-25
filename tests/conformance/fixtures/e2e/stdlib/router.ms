# conform: tags=aliasing,closures,faults,interpolation,modules,mutation,stdlib-http,stdlib-io,stdlib-net,stdlib-router,stdlib-sse,stdlib-testing,strings,testing,tier-io,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/router.ms
from "@std/testing.ms" import expect_equal, expect_true
from "@std/http.ms" import headers, reply, text, HttpError, HttpExchange, HttpMethod, HttpRequest, HttpResponse, HttpClientOptions, HttpServerOptions
from "@std/io.ms" import read_all
from "@std/net.ms" import network
from "@std/router.ms" import RouteParams, Router, RouterError
from "@std/sse.ms" import body_stream

def get(path: String) -> HttpRequest:
    return request(HttpMethod.Get, path)

def request(method: HttpMethod, path: String) -> HttpRequest:
    return HttpRequest(
        method: method, path: path, query: "", headers: headers(), body: "".to_bytes()
    )

def say(label: String) -> Callable[[HttpExchange, RouteParams], Result[Unit, HttpError]]:
    return lambda exchange, params: reply(exchange, text(200, label.clone()))

def show(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    let id = params.get("id").get("-")
    let rest = params.get("rest").get("-")
    return reply(exchange, text(200, f"{id}|{rest}"))

def body_of(response: HttpResponse) -> String:
    return response.body.decode_utf8().get("")

def allow_of(response: HttpResponse) -> String:
    let values = response.headers.text("Allow").get(none).get([])
    return values.join(",")

def router() -> Router:
    var r = Router()
    r.route(HttpMethod.Get, "/", say("root")).get()
    r.route(HttpMethod.Get, "/users", say("list")).get()
    r.route(HttpMethod.Post, "/users", say("create")).get()
    r.route(HttpMethod.Get, "/users/:id", show).get()
    r.route(HttpMethod.Get, "/files/*rest", show).get()
    return r

test "literal, parameter and wildcard routes":
    let r = router()
    try expect_equal(body_of(try r.call(get("/"))), "root")
    try expect_equal(body_of(try r.call(get("/users"))), "list")
    try expect_equal(body_of(try r.call(get("/users/42"))), "42|-")
    try expect_equal(body_of(try r.call(get("/files/a/b.txt"))), "-|a/b.txt")
    try expect_equal(body_of(try r.call(get("/files/"))), "-|")

test "unknown paths answer 404":
    let r = router()
    let response = try r.call(get("/nope"))
    try expect_equal(response.status, 404)
    try expect_equal(body_of(try r.call(get("/users/1/extra"))), "not found\n")
    try expect_equal((try r.call(get("/users/"))).status, 404)

test "a known path under another method answers 405 with Allow":
    let r = router()
    let response = try r.call(request(HttpMethod.Delete, "/users"))
    try expect_equal(response.status, 405)
    try expect_equal(allow_of(response), "GET, HEAD, OPTIONS, POST")

test "OPTIONS lists the methods without calling a handler":
    let r = router()
    let response = try r.call(request(HttpMethod.Options, "/users/7"))
    try expect_equal(response.status, 204)
    try expect_equal(allow_of(response), "GET, HEAD, OPTIONS")

test "HEAD is answered from the GET route without a body":
    let r = router()
    let response = try r.call(request(HttpMethod.Head, "/users"))
    try expect_equal(response.status, 200)
    try expect_equal(response.body.length(), 0)

test "the first matching route wins":
    var r = Router()
    r.route(HttpMethod.Get, "/a/:x", say("param")).get()
    r.route(HttpMethod.Get, "/a/b", say("literal")).get()
    try expect_equal(body_of(try r.call(get("/a/b"))), "param")

test "invalid and duplicate patterns are rejected":
    var r = Router()
    try expect_true(r.route(HttpMethod.Get, "users", say("x")).is_error())
    try expect_true(r.route(HttpMethod.Get, "/a/:", say("x")).is_error())
    try expect_true(r.route(HttpMethod.Get, "/a/*r/b", say("x")).is_error())
    try expect_true(r.route(HttpMethod.Get, "/a/:x/:x", say("x")).is_error())
    try expect_true(r.route(HttpMethod.Get, "/a//b", say("x")).is_error())
    r.route(HttpMethod.Get, "/a/:x", say("x")).get()
    try expect_true(r.route(HttpMethod.Get, "/a/:y", say("y")).is_error())
    r.route(HttpMethod.Post, "/a/:y", say("y")).get()

def tag(label: String) -> Callable[
    [HttpExchange, Callable[[], Result[Unit, HttpError]]], Result[Unit, HttpError]
]:
    return lambda exchange, next: tagged(label.clone(), exchange, next)

def tagged(
    label: String,
    exchange: HttpExchange,
    next: Callable[[], Result[Unit, HttpError]]
) -> Result[Unit, HttpError]:
    let seen = exchange.headers()
    try seen.append("X-Trail", label.to_bytes())
    return next()

def trail(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    let values = exchange.headers().text("X-Trail").get(none).get([])
    return reply(exchange, text(200, values.join(">")))

test "middleware wraps routes outermost first":
    var r = Router()
    r.use(tag("a"))
    r.use(tag("b"))
    r.route(HttpMethod.Get, "/t", trail).get()
    try expect_equal(body_of(try r.call(get("/t"))), "a>b")

test "middleware also wraps the 404 answer":
    var r = Router()
    r.use(tag("a"))
    try expect_equal((try r.call(get("/missing"))).status, 404)

def refuse(
    exchange: HttpExchange,
    next: Callable[[], Result[Unit, HttpError]]
) -> Result[Unit, HttpError]:
    return reply(exchange, text(401, "no"))

test "middleware may answer without calling the rest":
    var r = Router()
    r.use(refuse)
    r.route(HttpMethod.Get, "/t", say("never")).get()

    let response = try r.call(get("/t"))
    try expect_equal(response.status, 401)

def fail(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    return error(HttpError.Failed("boom"))

test "a handler error comes back from call":
    var r = Router()
    r.route(HttpMethod.Get, "/f", fail).get()
    try expect_true((r.call(get("/f"))).is_error())

test "a handler that sends nothing answers 204":
    var r = Router()
    r.route(HttpMethod.Get, "/n", lambda exchange, params: ok(())).get()
    try expect_equal((try r.call(get("/n"))).status, 204)

test "the router serves over a socket":
    let handler = router().handler()

    with let server = try network().serve("127.0.0.1:0", handler, HttpServerOptions()):
        with let client = try network().http_client(HttpClientOptions()):
            let response = try client.request(
                HttpMethod.Get, f"http://{server.address()}/users/9", headers()
            )
            try expect_equal(response.metadata().status, 200)

            let body = try read_all(body_stream(response))
            try expect_equal(body.decode_utf8().get(""), "9|-")

            let missing = try client.request(
                HttpMethod.Delete, f"http://{server.address()}/users", headers()
            )
            try expect_equal(missing.metadata().status, 405)

test "mount places a router under a prefix with its own middleware":
    var api = Router()
    api.use(tag("api"))
    api.route(HttpMethod.Get, "/", trail).get()
    api.route(HttpMethod.Get, "/items/:id", show).get()

    var r = Router()
    r.use(tag("top"))
    r.route(HttpMethod.Get, "/health", trail).get()
    r.mount("/api/v1", api).get()
    try expect_equal(body_of(try r.call(get("/api/v1"))), "top>api")
    try expect_equal(body_of(try r.call(get("/api/v1/items/5"))), "5|-")
    try expect_equal(body_of(try r.call(get("/health"))), "top")
    try expect_equal((try r.call(get("/items/5"))).status, 404)

test "mount rejects a trailing slash and a clashing route":
    var api = Router()
    api.route(HttpMethod.Get, "/x", say("x")).get()

    var r = Router()
    try expect_true(r.mount("/api/", api).is_error())
    r.mount("/api", api).get()
    try expect_true(r.mount("/api", api).is_error())
    r.mount("/", api).get()
    try expect_equal(body_of(try r.call(get("/x"))), "x")
