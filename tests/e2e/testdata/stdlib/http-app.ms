from "@std/sync.ms" import lock
from "@std/http.ms" import HttpMethod, HttpError, HttpServerOptions, headers, websocket_response, Request, Response, Body, Router, Server, serve, text_response, stream_response
from "@std/net.ms" import network
from "@std/io.ms" import WriteStream
from "@std/shared.ms" import share
from "@std/core.ms" import panic
from "@std/testing.ms" import expect_equal, expect_true, expect_fault

def test_text(response: Response) -> String:
    match response.body:
        case Buffered(data): return data.decode_utf8().get()
        case _: return ""

test "routes use literal precedence and preserve captured parameters":
    var routes = Router()
    routes.get(
        "/users/:id", lambda request: text_response(request.params.get("id").get())
    )
    routes.get("/users/me", lambda request: text_response("current"))
    try expect_equal(test_text(routes.handle(Request(path: "/users/me"))), "current")
    try expect_equal(test_text(routes.handle(Request(path: "/users/42"))), "42")
    try expect_equal(routes.handle(Request(path: "/missing")).status, 404)

test "method negotiation includes implicit HEAD and OPTIONS":
    var routes = Router()
    routes.get("/item", lambda request: text_response("item"))
    try expect_equal(
        routes.handle(Request(method: HttpMethod.Head, path: "/item")).status, 200
    )

    let response = routes.handle(Request(method: HttpMethod.Post, path: "/item"))
    try expect_equal(response.status, 405)
    try expect_equal(
        response.headers.text("Allow").get().get() [0], "GET, HEAD, OPTIONS"
    )
    try expect_equal(
        routes.handle(
            Request(method: HttpMethod.Options, path: "/item")
        ).status,
        204
    )

test "middleware wraps mounted routes and can short circuit":
    let calls = share(List[String]())
    var api = Router()
    api.get("/users", lambda request: text_response("users"))

    api.use(
        lambda request,
        next:
            with var log_guard = lock(calls):
                log_guard.value.append("child")
            return next(request)
    )

    var routes = Router()
    routes.mount("/api", api)

    routes.use(
        lambda request,
        next:
            with var log_guard = lock(calls):
                log_guard.value.append("before")

            let response = next(request)
            with var after_guard = lock(calls):
                after_guard.value.append("after")
            return response
    )

    try expect_equal(test_text(routes.handle(Request(path: "/api/users"))), "users")
    try expect_equal(calls.get().join(","), "before,child,after")

    var denied = Router()
    denied.get("/", lambda request: panic("must not reach handler"))
    denied.use(lambda request, next: text_response("unauthorized", 401))
    try expect_equal(denied.handle(Request()).status, 401)

test "duplicate shapes and repeated next calls fault":
    let fault = try expect_fault(
        lambda:
            var routes = Router()
            routes.get("/:one", lambda request: text_response("a"))
            routes.get("/:two", lambda request: text_response("b"))
    )

    try expect_true(fault.contains("ambiguous route"))

    let repeated = try expect_fault(
        lambda:
            var routes = Router()
            routes.get("/", lambda request: text_response("ok"))

            routes.use(
                lambda request,
                next:
                    next(request.clone())
                    return next(request)
            )

            routes.handle(Request())
    )

    try expect_true(repeated.contains("only once"))

from "@std/http.ms" import HttpClientOptions
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import duration, sleep

test "real HTTP streams responses without invoking a HEAD producer":
    let produced = share(0)
    var routes = Router()
    routes.get(
        "/events",
        lambda request: stream_response(
            lambda (var output: WriteStream):
                with var guard = lock(produced):
                    let count = guard.value
                    guard.value = count + 1

                try output.write("data: first\n\n")
                return output.write("data: second\n\n")
            ,
            content_type: "text/event-stream"
        )
    )

    let server = Server("127.0.0.1:0")

    with let group = TaskGroup[Result[Unit, HttpError]]():
        let owner = server.clone()
        let task = group.spawn(lambda channel: owner.run(routes.clone()))
        wait_ready(server)

        with let client = try network().http_client(HttpClientOptions()):
            with let response = try client.request(
                HttpMethod.Head, "http://" + server.address().get() + "/events",
                headers()
            ):
                try expect_equal(response.metadata().status, 200)
                try expect_true(response.read().get().is_none())

            try expect_equal(produced.get(), 0)

            with let response = try client.request(
                HttpMethod.Get, "http://" + server.address().get() + "/events",
                headers()
            ):
                var text = ""

                while True:
                    let chunk = try response.read()
                    if chunk.is_none(): break

                    text += chunk.get().decode_utf8().get()

                try expect_equal(text, "data: first\n\ndata: second\n\n")

            try expect_equal(produced.get(), 1)

        server.close()

        let result = try task.result()
        let finished = try result

test "request body stays lazy through rejecting middleware":
    var routes = Router()
    routes.post("/upload", lambda request: panic("must not read a rejected upload"))
    routes.use(lambda request, next: text_response("denied", 401))

    let server = Server(
        "127.0.0.1:0", HttpServerOptions(timeout: some(duration(2000000000)))
    )

    with let group = TaskGroup[Result[Unit, HttpError]]():
        let owner = server.clone()
        let task = group.spawn(lambda channel: owner.run(routes.clone()))
        wait_ready(server)

        with let socket = try network().connect(server.address().get()):
            try socket.write(
                "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000000\r\nExpect: 100-continue\r\nConnection: close\r\n\r\n"
            )

            let bytes = try socket.read()
            try expect_true(bytes.get().decode_utf8().get().contains("401"))

        server.close()

        let result = try task.result()
        let finished = try result

test "scoped server runs once and closes through an external owner":
    let server = Server("127.0.0.1:0")

    with let group = TaskGroup[Result[Unit, HttpError]]():
        let owner = server.clone()

        let task = group.spawn(
            lambda channel:
                var routes = Router()
                routes.get("/", lambda request: text_response("ready"))
                return owner.run(routes)
        )

        wait_ready(server)
        with let client = try network().http_client(HttpClientOptions()):
            with let response = try client.request(
                HttpMethod.Get, "http://" + server.address().get() + "/", headers()
            ):
                try expect_equal(response.metadata().status, 200)
        server.close()

        let completed = try task.result()
        let finished = try completed
        try expect_true(server.run(Router()).is_error())

test "mounted middleware sees missing routes and method refusals":
    var api = Router()
    api.get("/users", lambda request: text_response("users"))

    api.use(
        lambda request,
        next:
            let response = next(request)
            response.headers.append("X-Group", "api".to_bytes()).get()
            return response
    )

    var routes = Router()
    routes.mount("/api", api)

    for request in [
        Request(path: "/api/missing"),
        Request(method: HttpMethod.Post, path: "/api/users")
    ]:
        let response = routes.handle(request)
        try expect_equal(response.headers.text("X-Group").get().get() [0], "api")

test "retained middleware continuation cannot run after its scope":
    let saved = share(List[Callable[[Request], Response]]())
    var routes = Router()

    routes.use(
        lambda request,
        next:
            with var list_guard = lock(saved):
                list_guard.value.append(next)
            return text_response("short circuit")
    )

    routes.handle(Request())

    let report = try expect_fault(
        lambda:
            saved.get() [0](Request())
            return ()
    )

    try expect_true(report.contains("no longer active"))

test "application returning before serving is an error":
    try expect_true(serve("127.0.0.1:0", lambda server: ok(())).is_error())

# Bounded startup observation makes startup failures diagnostic instead of hanging.
def wait_ready(server: Server) -> Unit:
    var remaining = 2000

    while server.address().is_none() and remaining > 0:
        sleep(duration(1000000))
        remaining -= 1

    if server.address().is_none(): panic("server did not become ready")

test "automatic method responses preserve mounted middleware regardless of registration order":
    var api = Router()

    api.use(
        lambda request,
        next:
            let response = next(request)
            response.headers.append("X-Group", "api".to_bytes()).get()
            return response
    )

    api.get("/users", lambda request: text_response("users"))

    var routes = Router()
    routes.mount("/api", api)
    routes.post("/api/users", lambda request: text_response("created"))

    for method in [HttpMethod.Delete, HttpMethod.Options]:
        let response = routes.handle(Request(method: method, path: "/api/users"))
        try expect_equal(response.headers.text("X-Group").get().get() [0], "api")

test "nested mount collisions fail before registration":
    var nested = Router()
    nested.mount("/v1", Router())

    var routes = Router()
    routes.mount("/api/v1", Router())

    let report = try expect_fault(
        lambda:
            var copy = routes.clone()
            copy.mount("/api", nested)
            return ()
    )

    try expect_true(report.contains("duplicate mount prefix"))

test "discarding a bind failure cannot make serve succeed":
    with let listener = try network().listen("127.0.0.1:0"):
        let result = serve(
            listener.address(),
            lambda server:
                let failed = server.run(Router())
                return ok(())
        )

        try expect_true(result.is_error())

test "websocket handshake includes middleware headers and repeated cookies":
    var routes = Router()
    routes.get("/socket", lambda request: websocket_response(lambda socket: ok(())))

    routes.use(
        lambda request,
        next:
            let response = next(request)
            response.headers.append("X-Request-ID", "test-42".to_bytes()).get()
            response.headers.append("Set-Cookie", "a=1".to_bytes()).get()
            response.headers.append("Set-Cookie", "b=2".to_bytes()).get()
            return response
    )

    let server = Server("127.0.0.1:0")

    with let group = TaskGroup[Result[Unit, HttpError]]():
        let owner = server.clone()
        let task = group.spawn(lambda channel: owner.run(routes.clone()))
        wait_ready(server)

        with let socket = try network().connect(server.address().get()):
            try socket.write(
                "GET /socket HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
            )

            var head = ""

            while not head.contains("\r\n\r\n"):
                let chunk = try socket.read(some(1))
                if chunk.is_none(): break

                head += chunk.get().decode_utf8().get()

            try expect_true(head.contains("101 Switching Protocols"))
            try expect_true(head.contains("X-Request-ID: test-42\r\n"))
            try expect_true(head.contains("Set-Cookie: a=1\r\nSet-Cookie: b=2\r\n"))

        server.close()

        let result = try task.result()
        let finished = try result

test "nested root mounts retain middleware for missing routes and automatic OPTIONS":
    var leaf = Router()
    leaf.get("/users", lambda request: text_response("users"))

    leaf.use(
        lambda request,
        next:
            let response = next(request)
            response.headers.append("X-Leaf", "present".to_bytes()).get()
            return response
    )

    var child = Router()
    child.mount("/", leaf)

    var parent = Router()
    parent.mount("/api", child)

    for request in [
        Request(path: "/api/missing"),
        Request(method: HttpMethod.Options, path: "/api/users")
    ]:
        let response = parent.handle(request)
        try expect_equal(response.headers.text("X-Leaf").get().get() [0], "present")

test "bodyless statuses skip producers and retained writers expire":
    let retained = share(List[WriteStream]())
    var routes = Router()
    routes.get(
        "/empty",
        lambda request: stream_response(
            lambda output: panic("204 producer ran"), status: 204
        )
    )
    routes.get(
        "/cached",
        lambda request: stream_response(
            lambda output: panic("304 producer ran"), status: 304
        )
    )
    routes.get(
        "/stream",
        lambda request: stream_response(
            lambda (var output: WriteStream):
                try output.write("done")
                with var list_guard = lock(retained):
                    list_guard.value.append(output)
                return ok(())
        )
    )

    let server = Server("127.0.0.1:0")

    with let group = TaskGroup[Result[Unit, HttpError]]():
        let owner = server.clone()
        let task = group.spawn(lambda channel: owner.run(routes.clone()))
        wait_ready(server)

        with let client = try network().http_client(HttpClientOptions()):
            for path in ["/empty", "/cached"]:
                with let response = try client.request(
                    HttpMethod.Get, "http://" + server.address().get() + path, headers()
                ):
                    try expect_equal(
                        response.metadata().status, 204 if path == "/empty" else 304
                    )
                    try expect_true(response.read().get().is_none())

            with let response = try client.request(
                HttpMethod.Get, "http://" + server.address().get() + "/stream",
                headers()
            ):
                while (try response.read()).is_some(): continue

            var list = retained.get().clone()
            var writer = list.pop().get()
            try expect_true(writer.write("late").is_error())
            writer.close()

        server.close()

        let result = try task.result()
        let finished = try result
