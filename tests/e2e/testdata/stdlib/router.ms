import expect_equal, expect_true from "@std/test/test.ms"
import (
    from_io,
    headers,
    json,
    redirect,
    reply,
    text,
    HttpError,
    HttpExchange,
    HttpMethod,
    HttpRequest,
    HttpResponse,
    HttpClientOptions,
    HttpServerOptions
) from "@std/net/http.ms"
import IoError, read_all from "@std/io/io.ms"
import http_client, serve from "@std/net/net.ms"
import create, LogError, Transport from "@std/log.ms"
import Shared from "@std/concurrency/shared.ms"
import Bytes from "@std/bytes.ms"
import access_log, request_id, RouteParams, Router, RouterError, with_request_headers from "@std/net/router.ms"
import body_stream from "@std/net/sse.ms"

fn get(path: String) HttpRequest:
    return request(HttpMethod.Get, path)

fn request(method: HttpMethod, path: String) HttpRequest:
    return HttpRequest(
        method: method, path: path, query: "", headers: headers(), body: "".to_bytes()
    )

fn say(label: String) fn(var HttpExchange, RouteParams) Unit!HttpError:
    return fn var exchange, params: reply(var exchange, text(200, label.clone()))

fn show(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    let id = params.get_or("id", "-")
    let rest = params.get_or("rest", "-")
    return reply(var exchange, text(200, "{id}|{rest}"))

fn body_of(response: HttpResponse) String:
    return response.body.decode_utf8().get("")

fn allow_of(response: HttpResponse) String:
    let values = response.headers.values("Allow")
    return values.join(",")

fn router() Router:
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

fn head_reply(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    return reply(var exchange, text(202, "head"))

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

fn tag(
    label: String
) fn(var HttpExchange, fn(var HttpExchange) Unit!HttpError) Unit!HttpError:
    return fn var exchange, next: tagged(label.clone(), exchange, next)

fn tagged(
    label: String,
    exchange: HttpExchange,
    next: fn(var HttpExchange) Unit!HttpError
) Unit!HttpError:
    var seen = exchange.headers()
    try seen.append("X-Trail", label)

    var wrapped = with_request_headers(exchange, seen)
    return next(var wrapped)

fn trail(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    let values = exchange.headers().values("X-Trail")
    return reply(var exchange, text(200, values.join(">")))

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

fn refuse(var exchange: HttpExchange, next: fn(var HttpExchange) Unit!HttpError) Unit!HttpError:
    return reply(var exchange, text(401, "no"))

test "middleware may answer without calling the rest":
    var r = Router()
    r.use(refuse)
    r.get("/t", say("never")).get()

    let response = try r.call(get("/t"))
    try expect_equal(response.status, 401)

fn fail(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    return error(HttpError.Failed("boom"))

test "a handler error comes back from call":
    var r = Router()
    r.get("/f", fail).get()
    try expect_true((r.call(get("/f"))).is_error())

test "a handler that sends nothing answers 204":
    var r = Router()
    r.get("/n", fn var exchange, params: ok(unit)).get()
    try expect_equal((try r.call(get("/n"))).status, 204)

fn whole_response(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    let body = if exchange.path() == "/empty": "" else: "done"

    try reply(var exchange, text(200, body))

    for extra in ["extra", ""]:
        let written = exchange.write(extra)
        if written.is_ok(): return error(HttpError.Failed("write after send succeeded"))
        if written.err() != IoError.InvalidInput: return error(
            HttpError.Failed("wrong write error")
        )

    return ok(unit)

test "a whole in-process response rejects subsequent writes":
    var r = Router()
    try r.get("/done", whole_response)
    try r.get("/empty", whole_response)
    try expect_equal(body_of(try r.call(get("/done"))), "done")
    try expect_equal(body_of(try r.call(get("/empty"))), "")

fn small_reads(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    let first = try exchange.read(1).map_error(from_io)
    let second = try exchange.read(2).map_error(from_io)
    let end = try exchange.read(1).map_error(from_io)
    let a = first.get(Bytes([])).decode_utf8().get("")
    let b = second.get(Bytes([])).decode_utf8().get("")
    return reply(var exchange, text(200, "{a}|{b}|{end.is_none()}"))

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

fn read_sizes(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    let limit: Int? = if params.get_or("mode", "") == "default": none else: 100000

    let first = try exchange.read(limit).map_error(from_io)
    let second = try exchange.read(limit).map_error(from_io)
    let end = try exchange.read(limit).map_error(from_io)
    let a = first.get(Bytes([])).length()
    let b = second.get(Bytes([])).length()
    return reply(var exchange, text(200, "{a}|{b}|{end.is_none()}"))

test "in-process reads cap default and explicit chunks at 65536 bytes":
    var r = Router()
    try r.post("/:mode", read_sizes)

    for mode in ["default", "explicit"]:
        let response = try r.call(
            HttpRequest(
                method: HttpMethod.Post, path: "/{mode}", query: "", headers: headers(),
                body: "x".repeat(65537).get("").to_bytes()
            )
        )
        try expect_equal(body_of(response), "65536|1|true")

fn read_empty(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    let first = try exchange.read().map_error(from_io)
    let second = try exchange.read().map_error(from_io)
    return reply(var exchange, text(200, "{first.is_none()}|{second.is_none()}"))

test "in-process reads report EOF immediately for an empty body":
    var r = Router()
    try r.get("/", read_empty)
    try expect_equal(body_of(try r.call(get("/"))), "true|true")

fn invalid_reads(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    for limit in [0, -1]:
        let read = exchange.read(limit)
        if read.is_ok(): return error(HttpError.Failed("invalid read size accepted"))
        if read.err() != IoError.InvalidInput: return error(
            HttpError.Failed("wrong read error")
        )

    return small_reads(var exchange, params)

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
    let server = try serve("127.0.0.1:0", handler, HttpServerOptions())
    let client = try http_client(HttpClientOptions())
    let response = try client.request(
        HttpMethod.Get, "http://{server.address()}/users/9", headers()
    )
    try expect_equal(response.metadata().status, 200)

    let body = try read_all(body_stream(response))
    try expect_equal(body.decode_utf8().get(""), "9|-")

    let missing = try client.request(
        HttpMethod.Delete, "http://{server.address()}/users", headers()
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

fn answer(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    return reply(var exchange, try json(201, Answer(name: "ok", count: 2)))

fn moved(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    return reply(var exchange, try redirect("/elsewhere"))

test "json and redirect build responses":
    var r = Router()
    r.get("/j", answer).get()
    r.get("/m", moved).get()

    let sent = try r.call(get("/j"))
    try expect_equal(sent.status, 201)
    try expect_equal(body_of(sent), "\{\"name\":\"ok\",\"count\":2\}")
    try expect_equal(sent.headers.values("Content-Type").join(","), "application/json")

    let moved_to = try r.call(get("/m"))
    try expect_equal(moved_to.status, 303)
    try expect_equal(moved_to.headers.values("Location").join(","), "/elsewhere")

fn echo_id(var exchange: HttpExchange, params: RouteParams) Unit!HttpError:
    let seen = exchange.headers().values("X-Request-Id")
    return reply(var exchange, text(200, seen.join(",")))

fn id_of(response: HttpResponse) String:
    return response.headers.values("X-Request-Id").join(",")

test "request_id keeps a usable id and makes one otherwise":
    var r = Router()
    r.use(request_id())
    r.get("/i", echo_id).get()

    let fresh = try r.call(get("/i"))
    try expect_equal(id_of(fresh).length(), 36)
    try expect_equal(body_of(fresh), id_of(fresh))

    var incoming = get("/i")
    incoming.headers.append("X-Request-Id", "abc-123").get()

    let kept = try r.call(incoming)
    try expect_equal(id_of(kept), "abc-123")
    try expect_equal(body_of(kept), "abc-123")

    var bad = get("/i")
    bad.headers.append("X-Request-Id", "has space").get()
    try expect_equal(id_of(try r.call(bad)).length(), 36)
    try expect_equal(id_of(try r.call(get("/missing"))).length(), 36)

type Sink:
    lines: Shared[List[String]]

impl Transport for Sink:
    var fn write(data: String) Unit!LogError:
        self.lines.append(data.clone())
        return ok(unit)

    var fn write_bytes(data: Bytes) Unit!LogError:
        return self.write(data.decode_utf8().get(""))

    fn flush() Unit!LogError:
        return ok(unit)

    fn close() Unit:
        return unit

fn logged(lines: Shared[List[String]]) String:
    return lines.join("")

test "access_log writes one record per request":
    let lines = Shared(List[String]())
    let logger = (create(Sink(lines: lines), timestamp: false)).get()
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
