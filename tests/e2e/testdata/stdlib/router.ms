import (
	Bytes from "@std/bytes.ms",
	LoggerOptions, Transport, create from "@std/log.ms",
	HttpClientOptions,
	HttpExchange,
	HttpMethod,
	HttpRequest,
	HttpResponse,
	HttpServerOptions,
	headers,
	json,
	redirect,
	reply,
	text from "@std/net/http.ms",
	http_client, serve from "@std/net/net.ms",
	RouteParams,
	Router,
	access_log,
	request_id,
	with_request_headers from "@std/net/router.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok, expect_true from "@std/test/test.ms",

	read_to_end from "./support/conn.ms",
)

fn get(path: String) HttpRequest:
	return request(HttpMethod.Get, path)

fn request(method: HttpMethod, path: String) HttpRequest:
	return HttpRequest(
		method: method, path: path, query: "", headers: headers(), body: "".to_bytes()
	)

fn say(label: String) fn(var HttpExchange, RouteParams) Unit!:
	return fn var exchange, params: reply(var exchange, text(200, label.clone()))

fn show(var exchange: HttpExchange, params: RouteParams) Unit!:
	id := params.get_or("id", "-")
	rest := params.get_or("rest", "-")
	return reply(var exchange, text(200, "{id}|{rest}"))

fn body_of(response: HttpResponse) String:
	return response.body.decode_utf8().get("")

fn allow_of(response: HttpResponse) String:
	values := response.headers.values("Allow")
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
	r := router()
	expect_equal(body_of(r.call(get("/"))?), "root")?
	expect_equal(body_of(r.call(get("/users"))?), "list")?
	expect_equal(body_of(r.call(get("/users/42"))?), "42|-")?
	expect_equal(body_of(r.call(get("/files/a/b.txt"))?), "-|a/b.txt")?
	expect_equal(body_of(r.call(get("/files/"))?), "-|")?

test "unknown paths answer 404":
	r := router()
	response := r.call(get("/nope"))?
	expect_equal(response.status, 404)?
	expect_equal(body_of(r.call(get("/users/1/extra"))?), "not found\n")?
	expect_equal((r.call(get("/users/"))?).status, 404)?

test "a known path under another method answers 405 with Allow":
	r := router()
	response := r.call(request(HttpMethod.Delete, "/users"))?
	expect_equal(response.status, 405)?
	expect_equal(allow_of(response), "GET, HEAD, OPTIONS, POST")?

test "OPTIONS lists the methods without calling a handler":
	r := router()
	response := r.call(request(HttpMethod.Options, "/users/7"))?
	expect_equal(response.status, 204)?
	expect_equal(allow_of(response), "GET, HEAD, OPTIONS")?

test "OPTIONS * lists the methods of every route":
	r := router()
	response := r.call(request(HttpMethod.Options, "*"))?
	expect_equal(response.status, 204)?
	expect_equal(allow_of(response), "GET, HEAD, OPTIONS, POST")?

test "HEAD is answered from the GET route without a body":
	r := router()
	response := r.call(request(HttpMethod.Head, "/users"))?
	expect_equal(response.status, 200)?
	expect_equal(response.body.length(), 0)?

fn stream_parts(var exchange: HttpExchange, params: RouteParams) Unit!:
	exchange.send_headers(200, headers())?
	exchange.write("one")?
	exchange.write("two")?

test "a streaming GET route answers HEAD, dropping the body writes":
	var r = Router()
	r.get("/s", stream_parts).get()

	head := r.call(request(HttpMethod.Head, "/s"))?
	expect_equal(head.status, 200)?
	expect_equal(head.body.length(), 0)?
	expect_equal(body_of(r.call(get("/s"))?), "onetwo")?

	server := serve("127.0.0.1:0", r.handler(), HttpServerOptions())?
	client := http_client(HttpClientOptions())?
	var over_socket = client.request(
		HttpMethod.Head, "http://{server.address()}/s", headers()
	)?
	expect_equal(over_socket.metadata.status, 200)?

	rest := read_to_end(var over_socket.body)?
	expect_equal(rest.length(), 0)?

test "the first matching route wins":
	var r = Router()
	r.get("/a/:x", say("param")).get()
	r.get("/a/b", say("literal")).get()
	expect_equal(body_of(r.call(get("/a/b"))?), "param")?

fn head_reply(var exchange: HttpExchange, params: RouteParams) Unit!:
	return reply(var exchange, text(202, "head"))

test "explicit HEAD routes take precedence over GET fallback":
	var r = Router()
	r.get("/a/:id", say("get"))?
	r.head("/a/:id", head_reply)?
	r.head("/a/fixed", say("later"))?

	response := r.call(request(HttpMethod.Head, "/a/fixed"))?
	expect_equal(response.status, 202)?
	expect_equal(response.body.length(), 0)?
	expect_equal(body_of(r.call(get("/a/fixed"))?), "get")?

test "invalid and duplicate patterns are rejected":
	var r = Router()
	expect_true(r.get("users", say("x")).is_error())?
	expect_true(r.get("/a/:", say("x")).is_error())?
	expect_true(r.get("/a/*r/b", say("x")).is_error())?
	expect_true(r.get("/a/:x/:x", say("x")).is_error())?
	expect_true(r.get("/a//b", say("x")).is_error())?
	r.get("/a/:x", say("x")).get()
	expect_true(r.get("/a/:y", say("y")).is_error())?
	r.post("/a/:y", say("y")).get()

fn tag(label: String) fn(var HttpExchange, fn(var HttpExchange) Unit!) Unit!:
	return fn var exchange, next: tagged(label.clone(), var exchange, next)

fn tagged(
	label: String,
	var exchange: HttpExchange,
	next: fn(var HttpExchange) Unit!
) Unit!:
	var seen = exchange.headers()
	seen.append("X-Trail", label)?
	with_request_headers(var exchange, seen)
	return next(var exchange)

fn trail(var exchange: HttpExchange, params: RouteParams) Unit!:
	values := exchange.headers().values("X-Trail")
	return reply(var exchange, text(200, values.join(">")))

test "middleware wraps routes outermost first":
	var r = Router()
	r.use(tag("a"))
	r.use(tag("b"))
	r.get("/t", trail).get()
	expect_equal(body_of(r.call(get("/t"))?), "a>b")?

test "middleware also wraps the 404 answer":
	var r = Router()
	r.use(tag("a"))
	expect_equal((r.call(get("/missing"))?).status, 404)?

fn refuse(var exchange: HttpExchange, next: fn(var HttpExchange) Unit!) Unit!:
	return reply(var exchange, text(401, "no"))

test "middleware may answer without calling the rest":
	var r = Router()
	r.use(refuse)
	r.get("/t", say("never")).get()

	response := r.call(get("/t"))?
	expect_equal(response.status, 401)?

fn fail(var exchange: HttpExchange, params: RouteParams) Unit!:
	return error(Error("boom", kind: "EIO"))

test "a handler error comes back from call":
	var r = Router()
	r.get("/f", fail).get()
	expect_true((r.call(get("/f"))).is_error())?

test "a handler that sends nothing answers 204":
	var r = Router()
	r.get("/n", fn var exchange, params: ok(unit)).get()
	expect_equal((r.call(get("/n"))?).status, 204)?

fn whole_response(var exchange: HttpExchange, params: RouteParams) Unit!:
	body := if exchange.path() == "/empty": "" else: "done"
	whole := text(200, body)
	exchange.send(whole.status, whole.headers, whole.body)?

	for extra in ["extra", ""]:
		written := exchange.write(extra)
		if written.is_ok(): return error(
			Error("write after send succeeded", kind: "EIO")
		)
		if written.err().kind != "EINVAL": return error(
			Error("wrong write error", kind: "EIO")
		)

test "a whole in-process response rejects subsequent writes":
	var r = Router()
	r.get("/done", whole_response)?
	r.get("/empty", whole_response)?
	expect_equal(body_of(r.call(get("/done"))?), "done")?
	expect_equal(body_of(r.call(get("/empty"))?), "")?

fn small_reads(var exchange: HttpExchange, params: RouteParams) Unit!:
	first := exchange.read(1)?
	second := exchange.read(2)?
	end := exchange.read(1)?
	a := first.get(Bytes([])).decode_utf8().get("")
	b := second.get(Bytes([])).decode_utf8().get("")
	return reply(var exchange, text(200, "{a}|{b}|{end.is_none()}"))

test "in-process reads retain the unread body after a bounded chunk":
	var r = Router()
	r.post("/", small_reads)?

	response := r.call(
		HttpRequest(
			method: HttpMethod.Post, path: "/", query: "", headers: headers(),
			body: "abc".to_bytes()
		)
	)?
	expect_equal(body_of(response), "a|bc|true")?

fn read_sizes(var exchange: HttpExchange, params: RouteParams) Unit!:
	limit: Int? := if params.get_or("mode", "") == "default": none else: 100000
	first := exchange.read(limit)?
	second := exchange.read(limit)?
	end := exchange.read(limit)?
	a := first.get(Bytes([])).length()
	b := second.get(Bytes([])).length()
	return reply(var exchange, text(200, "{a}|{b}|{end.is_none()}"))

test "in-process reads cap default and explicit chunks at 65536 bytes":
	var r = Router()
	r.post("/:mode", read_sizes)?

	for mode in ["default", "explicit"]:
		response := r.call(
			HttpRequest(
				method: HttpMethod.Post, path: "/{mode}", query: "", headers: headers(),
				body: "x".repeat(65537).get("").to_bytes()
			)
		)?
		expect_equal(body_of(response), "65536|1|true")?

fn read_empty(var exchange: HttpExchange, params: RouteParams) Unit!:
	first := exchange.read()?
	second := exchange.read()?
	return reply(var exchange, text(200, "{first.is_none()}|{second.is_none()}"))

test "in-process reads report EOF immediately for an empty body":
	var r = Router()
	r.get("/", read_empty)?
	expect_equal(body_of(r.call(get("/"))?), "true|true")?

fn invalid_reads(var exchange: HttpExchange, params: RouteParams) Unit!:
	for limit in [0, -1]:
		read := exchange.read(limit)
		if read.is_ok(): return error(Error("invalid read size accepted", kind: "EIO"))
		if read.err().kind != "EINVAL": return error(
			Error("wrong read error", kind: "EIO")
		)

	return small_reads(var exchange, params)

test "in-process reads reject nonpositive sizes without consuming input":
	var r = Router()
	r.post("/", invalid_reads)?

	response := r.call(
		HttpRequest(
			method: HttpMethod.Post, path: "/", query: "", headers: headers(),
			body: "abc".to_bytes()
		)
	)?
	expect_equal(body_of(response), "a|bc|true")?

test "the router serves over a socket":
	handler := router().handler()
	server := serve("127.0.0.1:0", handler, HttpServerOptions())?
	client := http_client(HttpClientOptions())?
	var response = client.request(
		HttpMethod.Get, "http://{server.address()}/users/9", headers()
	)?
	expect_equal(response.metadata.status, 200)?

	body := read_to_end(var response.body)?
	expect_equal(body.decode_utf8().get(""), "9|-")?

	missing := client.request(
		HttpMethod.Delete, "http://{server.address()}/users", headers()
	)?
	expect_equal(missing.metadata.status, 405)?

test "mount places a router under a prefix with its own middleware":
	var api = Router()
	api.use(tag("api"))
	api.get("/", trail).get()
	api.get("/items/:id", show).get()

	var r = Router()
	r.use(tag("top"))
	r.get("/health", trail).get()
	r.mount("/api/v1", api).get()
	expect_equal(body_of(r.call(get("/api/v1"))?), "top>api")?
	expect_equal(body_of(r.call(get("/api/v1/items/5"))?), "5|-")?
	expect_equal(body_of(r.call(get("/health"))?), "top")?
	expect_equal((r.call(get("/items/5"))?).status, 404)?

fn x_router() Router:
	var api = Router()
	api.get("/x", say("x")).get()
	return api

test "mount rejects a trailing slash and a clashing route":
	var r = Router()
	expect_true(r.mount("/api/", x_router()).is_error())?
	r.mount("/api", x_router()).get()
	expect_true(r.mount("/api", x_router()).is_error())?
	r.mount("/", x_router()).get()
	expect_equal(body_of(r.call(get("/x"))?), "x")?

test "a mounted router keeps the groups of the routers mounted into it":
	var inner = Router()
	inner.use(tag("inner"))
	inner.get("/", trail).get()

	var mid = Router()
	mid.use(tag("mid"))
	mid.get("/own", trail).get()
	mid.mount("/inner", inner).get()

	var r = Router()
	r.use(tag("top"))
	r.mount("/mid", mid).get()
	r.get("/plain", trail).get()
	expect_equal(body_of(r.call(get("/mid/inner"))?), "top>mid>inner")?
	expect_equal(body_of(r.call(get("/mid/own"))?), "top>mid")?
	expect_equal(body_of(r.call(get("/plain"))?), "top")?

type Answer:
	name: String
	count: Int

fn answer(var exchange: HttpExchange, params: RouteParams) Unit!:
	return reply(var exchange, json(201, Answer(name: "ok", count: 2))?)

fn moved(var exchange: HttpExchange, params: RouteParams) Unit!:
	return reply(var exchange, redirect("/elsewhere")?)

test "json and redirect build responses":
	var r = Router()
	r.get("/j", answer).get()
	r.get("/m", moved).get()

	sent := r.call(get("/j"))?
	expect_equal(sent.status, 201)?
	expect_equal(body_of(sent), "\{\"name\":\"ok\",\"count\":2\}")?
	expect_equal(sent.headers.values("Content-Type").join(","), "application/json")?

	moved_to := r.call(get("/m"))?
	expect_equal(moved_to.status, 303)?
	expect_equal(moved_to.headers.values("Location").join(","), "/elsewhere")?

fn echo_id(var exchange: HttpExchange, params: RouteParams) Unit!:
	seen := exchange.headers().values("X-Request-Id")
	return reply(var exchange, text(200, seen.join(",")))

fn id_of(response: HttpResponse) String:
	return response.headers.values("X-Request-Id").join(",")

test "request_id keeps a usable id and makes one otherwise":
	var r = Router()
	r.use(request_id())
	r.get("/i", echo_id).get()

	fresh := r.call(get("/i"))?
	expect_equal(id_of(fresh).length(), 36)?
	expect_equal(body_of(fresh), id_of(fresh))?

	var incoming = get("/i")
	incoming.headers.append("X-Request-Id", "abc-123").get()

	kept := r.call(incoming)?
	expect_equal(id_of(kept), "abc-123")?
	expect_equal(body_of(kept), "abc-123")?

	var bad = get("/i")
	bad.headers.append("X-Request-Id", "has space").get()
	expect_equal(id_of(r.call(bad)?).length(), 36)?
	expect_equal(id_of(r.call(get("/missing"))?).length(), 36)?

type Sink:
	path: String

fn Sink.write(data: String) Unit!:
	return append_file(self.path, data).wait()

fn Sink.write_bytes(data: Bytes) Unit!:
	return self.write(data.decode_utf8().get(""))

fn Sink.flush() Unit!:
	return ok(unit)

fn Sink.duplicate() Transport!:
	return ok(Sink(self.path.clone()))

fn Sink.close() Unit:
	return unit

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

test "access_log writes one record per request":
	dir := temporary("ms-router-log-") | expect_ok?
	lines := "{dir.path()}/lines"
	logger := (create(Sink(path: lines.clone()), LoggerOptions(timestamp: false))).get()
	var r = Router()
	r.use(access_log(logger))
	r.get("/a", say("hello")).get()
	expect_equal((r.call(get("/a"))?).status, 200)?
	expect_equal((r.call(get("/nope"))?).status, 404)?

	text_out := logged(lines.clone())
	expect_true(text_out.contains("\"path\":\"/a\""))?
	expect_true(text_out.contains("\"status\":200"))?
	expect_true(text_out.contains("\"bytes\":5"))?
	expect_true(text_out.contains("\"status\":404"))?
	expect_equal(text_out.lines().length(), 2)?

fn no_content(var exchange: HttpExchange, params: RouteParams) Unit!:
	return exchange.send(204, headers(), "ignored".to_bytes())

test "access_log counts only the body bytes that are sent":
	dir := temporary("ms-router-log-head-") | expect_ok?
	lines := "{dir.path()}/lines"
	logger := (create(Sink(path: lines.clone()), LoggerOptions(timestamp: false))).get()
	var r = Router()
	r.use(access_log(logger))
	r.get("/a", say("hello")).get()
	r.get("/s", stream_parts).get()
	r.get("/n", no_content).get()

	head := r.call(request(HttpMethod.Head, "/a"))?
	expect_equal(head.body.length(), 0)?

	streamed := r.call(request(HttpMethod.Head, "/s"))?
	expect_equal(streamed.body.length(), 0)?

	empty := r.call(get("/n"))?
	expect_equal(empty.status, 204)?
	expect_equal((r.call(get("/a"))?).status, 200)?
	expect_equal(body_of(r.call(get("/s"))?), "onetwo")?

	records := logged(lines.clone()).lines()
	expect_equal(records.length(), 5)?
	expect_true(records[0].contains("\"method\":\"HEAD\""))?
	expect_true(records[0].contains("\"bytes\":0"))?
	expect_true(records[1].contains("\"bytes\":0"))?
	expect_true(records[2].contains("\"status\":204"))?
	expect_true(records[2].contains("\"bytes\":0"))?
	expect_true(records[3].contains("\"bytes\":5"))?
	expect_true(records[4].contains("\"bytes\":6"))?

test "verb helpers register their method":
	var r = Router()
	r.put("/v", say("put"))?
	r.patch("/v", say("patch"))?
	r.delete("/v", say("delete"))?
	r.options("/o", say("options"))?
	expect_equal(body_of(r.call(request(HttpMethod.Put, "/v"))?), "put")?
	expect_equal(body_of(r.call(request(HttpMethod.Patch, "/v"))?), "patch")?
	expect_equal(body_of(r.call(request(HttpMethod.Delete, "/v"))?), "delete")?
	expect_equal(body_of(r.call(request(HttpMethod.Options, "/o"))?), "options")?
	expect_equal((r.call(request(HttpMethod.Post, "/v"))?).status, 405)?
