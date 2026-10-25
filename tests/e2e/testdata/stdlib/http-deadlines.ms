from "@std/http.ms" import HttpRequest, HttpResponse, HttpExchange, HttpError, HttpMethod, HttpServerOptions, headers
from "@std/net.ms" import network
from "@std/time.ms" import sleep, clock
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal, expect_true

def delayed(request: HttpRequest) -> HttpResponse:
    if request.path == "/slow": sleep(5.seconds)

    if request.path == "/children":
        with TaskGroup[Unit]() as children:
            let _child = children.spawn(lambda channel: sleep(5.seconds))
            let _joined = children.wait()

    return HttpResponse(200, headers(), "done".to_bytes())

def delayed_stream(exchange: HttpExchange) -> Result[Unit, HttpError]:
    if exchange.path() == "/slow": sleep(5.seconds)
    try exchange.send_headers(200, headers())
    exchange.write("done").get()
    return ok(())

test "request deadlines cancel sleeping callbacks and do not poison later work":
    with try network().serve(
        "127.0.0.1:0", delayed,
        HttpServerOptions(timeout: 50.milliseconds, grace: 1.seconds)
    ) as server:
        for path in ["/slow", "/children"]:
            let began = clock().now()
            let response = try network().request(
                HttpMethod.Get, f"http://{server.address()}{path}", headers(),
                timeout: 2.seconds
            )
            try expect_equal(response.head.status, 504)
            try expect_true(clock().now().difference(began) < 1.seconds)

            let healthy = try network().request(
                HttpMethod.Get, f"http://{server.address()}/fast", headers(),
                timeout: 2.seconds
            )
            try expect_equal(healthy.head.status, 200)

test "streaming callback deadlines cancel sleeps and preserve later work":
    with try network().serve_stream(
        "127.0.0.1:0", delayed_stream,
        HttpServerOptions(timeout: 50.milliseconds, grace: 1.seconds)
    ) as server:
        let response = try network().request(
            HttpMethod.Get, f"http://{server.address()}/slow", headers(),
            timeout: 2.seconds
        )
        try expect_equal(response.head.status, 504)

        let healthy = try network().request(
            HttpMethod.Get, f"http://{server.address()}/fast", headers(),
            timeout: 2.seconds
        )
        try expect_equal(healthy.head.status, 200)

from "@std/http.ms" import Server, Router, text_response
from "@std/shared.ms" import Shared, share
from "@std/core.ms" import Closeable, panic
from "@std/bytes.ms" import Bytes

type Payload:
    bytes: Bytes
    closed: Shared[Int]

impl Closeable for Payload:
    var def close() -> Unit:
        let count = self.closed.take()
        self.closed.put(count + 1)

def request_status(server: Server, path: String) -> Int:
    return (
        network()
        .request(
            HttpMethod.Get, f"http://{server.address().get()}{path}", headers()
        )
        .get()
        .head
        .status
    )

test "application dispatch and with payloads recover after faults and deadlines":
    let closed = share(0)
    let server = Server("127.0.0.1:0", HttpServerOptions(timeout: 20.milliseconds))

    with TaskGroup[Result[Unit, HttpError]]() as tasks:
        let owner = server.clone()

        let running = tasks.spawn(
            lambda channel:
                var routes = Router()
                routes.use(lambda request, next: next(request))
                routes.get(
                    "/slow",
                    lambda request:
                        with Payload(
                            "x".repeat(
                                65536
                            ).get().to_bytes(),
                            closed
                        ) as payload:
                            sleep(5.seconds)
                            return text_response("late")
                )
                routes.get(
                    "/fault",
                    lambda request:
                        with Payload(
                            "x".repeat(
                                65536
                            ).get().to_bytes(),
                            closed
                        ) as payload:
                            panic("expected cleanup regression fault")
                            return text_response("unreachable")
                )
                return owner.run(routes)
        )

        while server.address().is_none(): sleep(1.milliseconds)
        try expect_equal(request_status(server, "/slow"), 504)
        try expect_equal(request_status(server, "/fault"), 500)

        for index in 0..16:
            try expect_equal(request_status(server, "/slow"), 504)
            try expect_equal(request_status(server, "/fault"), 500)

        try expect_equal(closed.get(), 34)
        try expect_equal(server.stats().active_requests, 0)
        server.close()

        let result = try running.result()
        let done = try result
