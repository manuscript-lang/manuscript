from "@std/testing.ms" import expect_true, expect_equal
from "@std/http.ms" import Server, Router, HttpError, HttpMethod, HttpServerOptions, headers, serve, workers, processes, text_response, stream_response, HttpClientOptions
from "@std/net.ms" import network, TlsOptions
from "@std/tasks.ms" import TaskGroup
from "@std/io.ms" import WriteStream
from "@std/time.ms" import sleep
from "@std/collections.ms" import range

def exercise_members(server: Server) -> Result[Unit, HttpError]:
    while not server.state.get().released:
        sleep(1.milliseconds)

    var identities = Set[String]()

    for attempt in range(0, 128):
        let response = try network().request(
            HttpMethod.Get, f"http://{server.address().get()}/", headers(),
            timeout: 2.seconds
        )
        identities.add(response.body.decode_utf8().get())
        if identities.length() == server.member_count: return ok(())

    return error(HttpError.Failed("requests did not reach every member"))

def exercise_and_stop(server: Server) -> Result[Unit, HttpError]:
    let result = exercise_members(server.clone())
    server.close()
    return result

def application(server: Server) -> Result[Unit, HttpError]:
    let identity = server.member_index.to_string()
    var routes = Router()
    routes.get("/", lambda request: text_response(identity))

    with TaskGroup[Result[Unit, HttpError]]() as tasks:
        if server.member_index == 0:
            let copy = server.clone()
            let _test = tasks.spawn(lambda channel: exercise_and_stop(copy))

        try server.run(routes)

        let results = tasks.results()
        if results.is_error(): return error(HttpError.Failed(results.err().message()))

        for result in results.get():
            if result.is_error(): return error(result.err().clone())

    return ok(())

test "workers run complete applications on one bound address":
    try serve(
        "127.0.0.1:0", application, HttpServerOptions(grace: 0.seconds),
        workers(2, 5.seconds)
    )

test "processes run complete applications on one bound address":
    try serve(
        "127.0.0.1:0", application, HttpServerOptions(grace: 0.seconds),
        processes(2, 5.seconds, 2.seconds)
    )

def missing_run(server: Server) -> Result[Unit, HttpError]:
    return ok(())

def delayed_start(server: Server) -> Result[Unit, HttpError]:
    sleep(10.seconds)
    return server.run(Router())

test "worker startup failure rolls back every member":
    let result = serve("127.0.0.1:0", missing_run, execution: workers(2, 2.seconds))
    try expect_true(result.is_error())
    try serve(
        "127.0.0.1:0", application, HttpServerOptions(grace: 0.seconds),
        workers(2, 5.seconds)
    )

test "process startup failure rolls back every member":
    let result = serve(
        "127.0.0.1:0", missing_run, execution: processes(2, 2.seconds, 1.seconds)
    )
    try expect_true(result.is_error())
    try serve(
        "127.0.0.1:0", application, HttpServerOptions(grace: 0.seconds),
        processes(2, 5.seconds, 2.seconds)
    )

test "worker startup deadline cancels sleeping initialization":
    let result = serve(
        "127.0.0.1:0", delayed_start, execution: workers(2, 50.milliseconds)
    )
    try expect_equal(result.err(), HttpError.Timeout)

test "process startup deadline terminates sleeping initialization":
    let result = serve(
        "127.0.0.1:0", delayed_start,
        execution: processes(2, 50.milliseconds, 1.seconds)
    )
    try expect_equal(result.err(), HttpError.Timeout)

test "invalid execution counts fail before initialization":
    try expect_equal(
        serve("127.0.0.1:0", missing_run, execution: workers(0)).err(),
        HttpError.InvalidInput
    )
    try expect_equal(
        serve("127.0.0.1:0", missing_run, execution: processes(-1)).err(),
        HttpError.InvalidInput
    )

from "./support/certificates.ms" import certificate, private_key

def exercise_tls_members(server: Server) -> Result[Unit, HttpError]:
    while not server.state.get().released:
        sleep(1.milliseconds)

    for protocol in ["http/1.1", "h2"]:
        var identities = Set[String]()
        let tls = TlsOptions(
            server_name: "stdlib.test", roots_pem: certificate(), certificate_pem: "",
            private_key_pem: "", alpn: [protocol.clone()],
            require_client_certificate: False
        )
        var expected = "HTTP/1.1"
        if protocol == "h2": expected = "HTTP/2.0"

        for attempt in range(0, 128):
            with try network().http_client(HttpClientOptions(tls: tls.clone())) as client:
                var first = ""

                for path in ["/", "/stream", "/", "/stream"]:
                    with try client.request(
                        HttpMethod.Get, f"https://{server.address().get()}{path}",
                        headers()
                    ) as response:
                        if response.metadata().protocol != expected:
                            return error(HttpError.Failed("group ALPN mismatch"))

                        let body = response.read().get().get().decode_utf8().get()
                        if first == "": first = body.clone()
                        if body != first or not body.ends_with(expected):
                            return error(
                                HttpError.Failed(
                                    "connection changed member or protocol"
                                )
                            )

                        identities.add(body)

            if identities.length() == server.member_count: break

        if identities.length() != server.member_count:
            return error(HttpError.Failed("TLS requests did not reach every member"))

    return ok(())

def exercise_tls_and_stop(server: Server) -> Result[Unit, HttpError]:
    let result = exercise_tls_members(server.clone())
    server.close()
    return result

def tls_application(server: Server) -> Result[Unit, HttpError]:
    let identity = server.member_index.to_string()
    let buffered_identity = identity.clone()
    var routes = Router()
    routes.get(
        "/", lambda request: text_response(f"{buffered_identity}:{request.protocol}")
    )

    routes.get(
        "/stream",
        lambda request:
            let body = f"{identity}:{request.protocol}"
            return stream_response(lambda (var output: WriteStream): output.write(body))
    )

    with TaskGroup[Result[Unit, HttpError]]() as tasks:
        if server.member_index == 0:
            let copy = server.clone()
            let _test = tasks.spawn(lambda channel: exercise_tls_and_stop(copy))

        try server.run(routes)

        let results = tasks.results()
        if results.is_error(): return error(HttpError.Failed(results.err().message()))

        for result in results.get():
            if result.is_error(): return error(result.err().clone())

    return ok(())

def group_tls_options() -> HttpServerOptions:
    return HttpServerOptions(
        grace: 0.seconds,
        tls: TlsOptions(
            server_name: "", roots_pem: "", certificate_pem: certificate(),
            private_key_pem: private_key(), alpn: [], require_client_certificate: False
        )
    )

test "workers preserve TLS protocols and connection affinity for both body modes":
    try serve(
        "127.0.0.1:0", tls_application, group_tls_options(), workers(2, 5.seconds)
    )

test "processes preserve TLS protocols and connection affinity for both body modes":
    try serve(
        "127.0.0.1:0", tls_application, group_tls_options(),
        processes(2, 5.seconds, 2.seconds)
    )
