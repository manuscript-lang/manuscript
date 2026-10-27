from "@std/test.ms" import expect_equal, expect_true
from "@std/http.ms" import from_io, headers, json, redirect, reply, text, HttpError, HttpExchange, HttpMethod, HttpRequest, HttpResponse, HttpClientOptions, HttpServerOptions
from "@std/io.ms" import IoError, read_all
from "@std/net.ms" import network
from "@std/log.ms" import create, LogError, Transport
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/bytes.ms" import Bytes
from "@std/router.ms" import access_log, request_id, RouteParams, Router, RouterError
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
    let id = params.get_or("id", "-")
    let rest = params.get_or("rest", "-")
    return reply(exchange, text(200, f"{id}|{rest}"))

def body_of(response: HttpResponse) -> String:
    return response.body.decode_utf8().get("")

def allow_of(response: HttpResponse) -> String:
    let values = response.headers.values("Allow")
    return values.join(",")

def router() -> Router:
    var r = Router()
    r.get("/", say("root")).get()
    r.get("/users", say("list")).get()
    r.post("/users", say("create")).get()
    r.get("/users/:id", show).get()
    r.get("/files/*rest", show).get()
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
    r.get("/a/:x", say("param")).get()
    r.get("/a/b", say("literal")).get()
    try expect_equal(body_of(try r.call(get("/a/b"))), "param")

def head_reply(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    return reply(exchange, text(202, "head"))

test "explicit HEAD routes take precedence over GET fallback":
    var r = Router()
    try r.get("/a/:id", say("get"))
    try r.head("/a/:id", head_reply)
    try r.head("/a/fixed", say("later"))

    let response = try r.call(request(HttpMethod.Head, "/a/fixed"))
    try expect_equal(response.status, 202)
    try expect_equal(response.body.length(), 0)
    try expect_equal(body_of(try r.call(get("/a/fixed"))), "get")

test "invalid and duplicate patterns are rejected":
    var r = Router()
    try expect_true(r.get("users", say("x")).is_error())
    try expect_true(r.get("/a/:", say("x")).is_error())
    try expect_true(r.get("/a/*r/b", say("x")).is_error())
    try expect_true(r.get("/a/:x/:x", say("x")).is_error())
    try expect_true(r.get("/a//b", say("x")).is_error())
    r.get("/a/:x", say("x")).get()
    try expect_true(r.get("/a/:y", say("y")).is_error())
    r.post("/a/:y", say("y")).get()

def tag(label: String) -> Callable[
    [HttpExchange, Callable[[HttpExchange], Result[Unit, HttpError]]],
    Result[Unit, HttpError]
]:
    return lambda exchange, next: tagged(label.clone(), exchange, next)

def tagged(
    label: String,
    exchange: HttpExchange,
    next: Callable[[HttpExchange], Result[Unit, HttpError]]
) -> Result[Unit, HttpError]:
    let seen = exchange.headers()
    try seen.append("X-Trail", label)
    return next(exchange)

def trail(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    let values = exchange.headers().values("X-Trail")
    return reply(exchange, text(200, values.join(">")))

test "middleware wraps routes outermost first":
    var r = Router()
    r.use(tag("a"))
    r.use(tag("b"))
    r.get("/t", trail).get()
    try expect_equal(body_of(try r.call(get("/t"))), "a>b")

test "middleware also wraps the 404 answer":
    var r = Router()
    r.use(tag("a"))
    try expect_equal((try r.call(get("/missing"))).status, 404)

def refuse(
    exchange: HttpExchange,
    next: Callable[[HttpExchange], Result[Unit, HttpError]]
) -> Result[Unit, HttpError]:
    return reply(exchange, text(401, "no"))

test "middleware may answer without calling the rest":
    var r = Router()
    r.use(refuse)
    r.get("/t", say("never")).get()

    let response = try r.call(get("/t"))
    try expect_equal(response.status, 401)

def fail(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    return error(HttpError.Failed("boom"))

test "a handler error comes back from call":
    var r = Router()
    r.get("/f", fail).get()
    try expect_true((r.call(get("/f"))).is_error())

test "a handler that sends nothing answers 204":
    var r = Router()
    r.get("/n", lambda exchange, params: ok(())).get()
    try expect_equal((try r.call(get("/n"))).status, 204)

def whole_response(
    exchange: HttpExchange,
    params: RouteParams
) -> Result[Unit, HttpError]:
    let body = "" if exchange.path() == "/empty" else "done"

    try reply(exchange, text(200, body))

    for extra in ["extra", ""]:
        let written = exchange.write(extra)
        if written.is_ok(): return error(HttpError.Failed("write after send succeeded"))
        if written.err() != IoError.InvalidInput: return error(
            HttpError.Failed("wrong write error")
        )

    return ok(())

test "a whole in-process response rejects subsequent writes":
    var r = Router()
    try r.get("/done", whole_response)
    try r.get("/empty", whole_response)
    try expect_equal(body_of(try r.call(get("/done"))), "done")
    try expect_equal(body_of(try r.call(get("/empty"))), "")

def small_reads(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    let first = try exchange.read(some(1)).map_error(from_io)
    let second = try exchange.read(some(2)).map_error(from_io)
    let end = try exchange.read(some(1)).map_error(from_io)
    let a = first.get(Bytes([])).decode_utf8().get("")
    let b = second.get(Bytes([])).decode_utf8().get("")
    return reply(exchange, text(200, f"{a}|{b}|{end.is_none()}"))

test "in-process reads retain the unread body after a bounded chunk":
    var r = Router()
    try r.post("/", small_reads)

    let response = try r.call(
        HttpRequest(
            method: HttpMethod.Post, path: "/", query: "", headers: headers(),
            body: "abc".to_bytes()
        )
    )
    try expect_equal(body_of(response), "a|bc|true")

def read_sizes(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    let limit = none if params.get_or("mode", "") == "default" else some(100000)

    let first = try exchange.read(limit).map_error(from_io)
    let second = try exchange.read(limit).map_error(from_io)
    let end = try exchange.read(limit).map_error(from_io)
    let a = first.get(Bytes([])).length()
    let b = second.get(Bytes([])).length()
    return reply(exchange, text(200, f"{a}|{b}|{end.is_none()}"))

test "in-process reads cap default and explicit chunks at 65536 bytes":
    var r = Router()
    try r.post("/:mode", read_sizes)

    for mode in ["default", "explicit"]:
        let response = try r.call(
            HttpRequest(
                method: HttpMethod.Post, path: f"/{mode}", query: "",
                headers: headers(), body: "x".repeat(65537).get("").to_bytes()
            )
        )
        try expect_equal(body_of(response), "65536|1|true")

def read_empty(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    let first = try exchange.read().map_error(from_io)
    let second = try exchange.read().map_error(from_io)
    return reply(exchange, text(200, f"{first.is_none()}|{second.is_none()}"))

test "in-process reads report EOF immediately for an empty body":
    var r = Router()
    try r.get("/", read_empty)
    try expect_equal(body_of(try r.call(get("/"))), "true|true")

def invalid_reads(
    exchange: HttpExchange,
    params: RouteParams
) -> Result[Unit, HttpError]:
    for limit in [0, -1]:
        let read = exchange.read(some(limit))
        if read.is_ok(): return error(HttpError.Failed("invalid read size accepted"))
        if read.err() != IoError.InvalidInput: return error(
            HttpError.Failed("wrong read error")
        )

    return small_reads(exchange, params)

test "in-process reads reject nonpositive sizes without consuming input":
    var r = Router()
    try r.post("/", invalid_reads)

    let response = try r.call(
        HttpRequest(
            method: HttpMethod.Post, path: "/", query: "", headers: headers(),
            body: "abc".to_bytes()
        )
    )
    try expect_equal(body_of(response), "a|bc|true")

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
    api.get("/", trail).get()
    api.get("/items/:id", show).get()

    var r = Router()
    r.use(tag("top"))
    r.get("/health", trail).get()
    r.mount("/api/v1", api).get()
    try expect_equal(body_of(try r.call(get("/api/v1"))), "top>api")
    try expect_equal(body_of(try r.call(get("/api/v1/items/5"))), "5|-")
    try expect_equal(body_of(try r.call(get("/health"))), "top")
    try expect_equal((try r.call(get("/items/5"))).status, 404)

test "mount rejects a trailing slash and a clashing route":
    var api = Router()
    api.get("/x", say("x")).get()

    var r = Router()
    try expect_true(r.mount("/api/", api).is_error())
    r.mount("/api", api).get()
    try expect_true(r.mount("/api", api).is_error())
    r.mount("/", api).get()
    try expect_equal(body_of(try r.call(get("/x"))), "x")

type Answer:
    name: String
    count: Int

def answer(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    return reply(exchange, try json(201, Answer(name: "ok", count: 2)))

def moved(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    return reply(exchange, try redirect("/elsewhere"))

test "json and redirect build responses":
    var r = Router()
    r.get("/j", answer).get()
    r.get("/m", moved).get()

    let sent = try r.call(get("/j"))
    try expect_equal(sent.status, 201)
    try expect_equal(body_of(sent), "{\"name\":\"ok\",\"count\":2}")
    try expect_equal(sent.headers.values("Content-Type").join(","), "application/json")

    let moved_to = try r.call(get("/m"))
    try expect_equal(moved_to.status, 303)
    try expect_equal(moved_to.headers.values("Location").join(","), "/elsewhere")

def echo_id(exchange: HttpExchange, params: RouteParams) -> Result[Unit, HttpError]:
    let seen = exchange.headers().values("X-Request-Id")
    return reply(exchange, text(200, seen.join(",")))

def id_of(response: HttpResponse) -> String:
    return response.headers.values("X-Request-Id").join(",")

test "request_id keeps a usable id and makes one otherwise":
    var r = Router()
    r.use(request_id())
    r.get("/i", echo_id).get()

    let fresh = try r.call(get("/i"))
    try expect_equal(id_of(fresh).length(), 36)
    try expect_equal(body_of(fresh), id_of(fresh))

    let incoming = get("/i")
    incoming.headers.append("X-Request-Id", "abc-123").get()

    let kept = try r.call(incoming)
    try expect_equal(id_of(kept), "abc-123")
    try expect_equal(body_of(kept), "abc-123")

    let bad = get("/i")
    bad.headers.append("X-Request-Id", "has space").get()
    try expect_equal(id_of(try r.call(bad)).length(), 36)
    try expect_equal(id_of(try r.call(get("/missing"))).length(), 36)

type Sink:
    lines: Shared[List[String]]

impl Transport for Sink:
    var def write(data: String) -> Result[Unit, LogError]:
        with var guard = lock(self.lines):
            guard.value.append(data.clone())
        return ok(())

    var def write_bytes(data: Bytes) -> Result[Unit, LogError]:
        return self.write(data.decode_utf8().get(""))

    var def flush() -> Result[Unit, LogError]:
        return ok(())

    var def close() -> Unit:
        return ()

def logged(lines: Shared[List[String]]) -> String:
    with var guard = lock(lines):
        return guard.value.join("")

test "access_log writes one record per request":
    let lines = share(List[String]())
    let logger = (create(Sink(lines: lines), timestamp: some(False))).get()
    var r = Router()
    r.use(access_log(logger))
    r.get("/a", say("hello")).get()
    try expect_equal((try r.call(get("/a"))).status, 200)
    try expect_equal((try r.call(get("/nope"))).status, 404)

    let text_out = logged(lines)
    try expect_true(text_out.contains("\"path\":\"/a\""))
    try expect_true(text_out.contains("\"status\":200"))
    try expect_true(text_out.contains("\"bytes\":5"))
    try expect_true(text_out.contains("\"status\":404"))
    try expect_equal(text_out.lines().length(), 2)

test "verb helpers register their method":
    var r = Router()
    try r.put("/v", say("put"))
    try r.patch("/v", say("patch"))
    try r.delete("/v", say("delete"))
    try r.options("/o", say("options"))
    try expect_equal(body_of(try r.call(request(HttpMethod.Put, "/v"))), "put")
    try expect_equal(body_of(try r.call(request(HttpMethod.Patch, "/v"))), "patch")
    try expect_equal(body_of(try r.call(request(HttpMethod.Delete, "/v"))), "delete")
    try expect_equal(body_of(try r.call(request(HttpMethod.Options, "/o"))), "options")
    try expect_equal((try r.call(request(HttpMethod.Post, "/v"))).status, 405)
