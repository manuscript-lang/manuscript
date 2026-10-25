from "@std/http.ms" import HttpRequest, HttpResponse, HttpExchange, HttpError, HttpMethod, HttpServerOptions, headers
from "@std/net.ms" import network
from "@std/shared.ms" import share
from "@std/time.ms" import sleep
from "@std/testing.ms" import expect_equal, expect_true

def echo_metadata(request: HttpRequest) -> HttpResponse:
    return HttpResponse(
        200, headers(), f"{request.scheme}|{request.peer_address}".to_bytes()
    )

test "transport metadata ignores forwarded headers and event saturation preserves counters":
    with try network().serve(
        "127.0.0.1:0", echo_metadata, HttpServerOptions(event_capacity: 1)
    ) as server:
        let fields = headers()
        try fields.append("Forwarded", "for=evil;proto=https".to_bytes())
        try fields.append("X-Forwarded-For", "203.0.113.1".to_bytes())

        for path in ["/first?secret=hidden", "/second"]:
            let response = try network().request(
                HttpMethod.Get, f"http://{server.address()}{path}", fields
            )
            try expect_true(
                response.body.decode_utf8().get().starts_with(
                    "http|127.0.0.1:"
                )
            )

        let stats = server.stats()
        try expect_equal(stats.requests, 2)
        try expect_equal(stats.completed, 2)
        try expect_equal(stats.active_requests, 0)
        try expect_equal(stats.dropped_events, 1)

        let events = server.take_events()
        try expect_equal(events.length(), 1)
        try expect_equal(events[0].path, "/first")
        try expect_equal(events[0].status, 200)
        try expect_equal(events[0].outcome, "completed")
        try expect_equal(events[0].scheme, "http")
        try expect_equal(server.take_events().length(), 0)

test "retaining an exchange does not retain an event reservation":
    let held = share(List[HttpExchange]())

    let handler: Callable[[HttpExchange], Result[Unit, HttpError]] = lambda exchange:
        try exchange.send_headers(200, headers())
        exchange.write("done").get()

        var values = held.take()
        values.append(exchange)
        held.put(values)
        return ok(())

    with try network().serve_stream(
        "127.0.0.1:0", handler, HttpServerOptions(event_capacity: 1)
    ) as server:
        let response = try network().request(
            HttpMethod.Get, f"http://{server.address()}/", headers()
        )
        try expect_equal(response.head.status, 200)
        try expect_equal(held.get().length(), 1)
        try expect_equal(server.stats().active_requests, 0)
        try expect_equal(server.stats().completed, 1)
        try expect_equal(server.take_events().length(), 1)

test "deadline outcomes remain observable with delivery disabled":
    let handler: Callable[[HttpExchange], Result[Unit, HttpError]] = lambda exchange:
        sleep(2.seconds)
        return ok(())

    with try network().serve_stream(
        "127.0.0.1:0", handler, HttpServerOptions(timeout: 20.milliseconds)
    ) as server:
        let response = try network().request(
            HttpMethod.Get, f"http://{server.address()}/", headers()
        )
        try expect_equal(response.head.status, 504)
        try expect_equal(server.stats().timed_out, 1)
        try expect_equal(server.stats().active_requests, 0)
        try expect_equal(server.stats().dropped_events, 0)
        try expect_equal(server.take_events().length(), 0)

from "@std/http.ms" import Server, Router, text_response
from "@std/tasks.ms" import TaskGroup
from "@std/core.ms" import panic

test "router labels survive callback faults without logging route captures or query":
    let server = Server("127.0.0.1:0", HttpServerOptions(event_capacity: 4))

    with TaskGroup[Result[Unit, HttpError]]() as tasks:
        let owner = server.clone()

        let task = tasks.spawn(
            lambda channel:
                var routes = Router()

                routes.get(
                    "/users/:id",
                    lambda request:
                        if request.params.get("id").get() == "bad": panic("test fault")
                        return text_response("ok")
                )

                return owner.run(routes)
        )

        while server.address().is_none(): sleep(1.milliseconds)

        let good = try network().request(
            HttpMethod.Get, f"http://{server.address().get()}/users/42?secret=hidden",
            headers()
        )
        let bad = try network().request(
            HttpMethod.Get, f"http://{server.address().get()}/users/bad", headers()
        )
        try expect_equal(good.head.status, 200)
        try expect_equal(bad.head.status, 500)
        try expect_equal(server.stats().faulted, 1)

        let events = server.take_events()
        try expect_equal(events.length(), 2)
        try expect_equal(events[0].route, "/users/:id")
        try expect_equal(events[1].route, "/users/:id")
        server.close()

        let completed = try task.result()
        let served = try completed

test "pre-request protocol and idle failures are counted independently of request events":
    with try network().serve(
        "127.0.0.1:0", echo_metadata, HttpServerOptions(idle_timeout: 20.milliseconds)
    ) as server:
        try expect_true(server.is_ready())

        with try network().connect(server.address()) as socket:
            try socket.write("BAD REQUEST\r\n\r\n")

            while True:
                let chunk = try socket.read(timeout: 1.seconds)
                if chunk.is_none(): break

        try expect_equal(server.stats().protocol_errors, 1)
        try expect_equal(server.stats().requests, 0)
        with try network().connect(server.address()) as idle:
            try expect_true((try idle.read(timeout: 1.seconds)).is_none())
        try expect_equal(server.stats().connection_timeouts, 1)
        try expect_equal(server.stats().connections, 2)
        server.close()
        try expect_true(not server.is_ready())

from "@std/net.ms" import TlsOptions
from "@std/http.ms" import HttpClientOptions
from "./support/certificates.ms" import certificate, private_key

test "TLS metadata and events identify the direct HTTPS transport over both protocols":
    let tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: certificate(),
        private_key_pem: private_key(), alpn: [], require_client_certificate: False
    )

    with try network().serve(
        "127.0.0.1:0", echo_metadata, HttpServerOptions(tls: tls, event_capacity: 4)
    ) as server:
        for protocol in ["http/1.1", "h2"]:
            let client_tls = TlsOptions(
                server_name: "stdlib.test", roots_pem: certificate(),
                certificate_pem: "", private_key_pem: "", alpn: [protocol.clone()],
                require_client_certificate: False
            )

            with try network().http_client(HttpClientOptions(tls: client_tls)) as client:
                with try client.request(
                    HttpMethod.Get, f"https://{server.address()}/secure", headers()
                ) as response:
                    var text = ""

                    while True:
                        let chunk = try response.read()
                        if chunk.is_none(): break

                        text += chunk.get().decode_utf8().get()

                    try expect_true(text.starts_with("https|127.0.0.1:"))

        let events = server.take_events()
        try expect_equal(events.length(), 2)

        for event in events:
            try expect_equal(event.scheme, "https")
            try expect_true(event.peer_address.starts_with("127.0.0.1:"))
