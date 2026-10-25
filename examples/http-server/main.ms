from "@std/http.ms" import HttpError, HttpServerOptions, Request, Response, Router, Server, serve, workers, processes, text_response, stream_response, websocket_response, json_response, decode_json
from "@std/io.ms" import WriteStream, IoError
from "@std/net.ms" import WebSocket, WebSocketError
from "@std/json.ms" import JsonLimits
from "@std/web.ms" import bearer_token
from "@std/web_html.ms" import Html, html_response
from "@std/crypto.ms" import constant_time_equal
from "@std/process.ms" import arguments, control
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import sleep
from "@std/log.ms" import create, stdout_transport, record, LogLevel, LogError

# Development: API_TOKEN=<at-least-16-characters> ms run main.ms --watch -- local
# Production: ms build main.ms -o server; API_TOKEN=... ./server processes 4 127.0.0.1:8080
# workers runs complete handlers in isolates; processes also isolates process failures.
# Each application invocation owns its configuration, routes, logger and any scoped database clients.
type Greeting:
    name: String

type Message:
    message: String
    member: Int

def safety_headers(request: Request, next: Callable[[Request], Response]) -> Response:
    let response = next(request)
    response.headers.append("X-Content-Type-Options", "nosniff".to_bytes()).get()
    response.headers.append("Referrer-Policy", "same-origin".to_bytes()).get()
    response.headers.append("Cache-Control", "no-store".to_bytes()).get()
    return response

def authorized(request: Request, token: String) -> Bool:
    let supplied = bearer_token(request)
    return (
        supplied.is_ok()
        and supplied.get().is_some()
        and constant_time_equal(
            supplied.get().get().to_bytes(), token.to_bytes()
        )
    )

def authenticated(
    request: Request,
    next: Callable[[Request], Response],
    token: String
) -> Response:
    if not authorized(request, token):
        let response = text_response("Unauthorized", 401)
        response.headers.append("WWW-Authenticate", "Bearer".to_bytes()).get()
        return response

    return next(request)

def greet(request: Request, member: Int) -> Response:
    let decoded = decode_json[Greeting](
        request, JsonLimits(max_bytes: 4096, max_depth: 8, max_values: 16)
    )
    if decoded.is_error(): return text_response(decoded.err().message(), 400)

    let name = decoded.get().name.trim()
    if name.scalar_length() < 1 or name.scalar_length() > 80: return text_response(
        "name must contain 1 to 80 characters", 422
    )

    return json_response(Message("Hello, " + name, member)).get().clone()

def events(var output: WriteStream) -> Result[Unit, IoError]:
    var sequence = 0

    while sequence < 5:
        try output.write(f"id: {sequence}\nevent: tick\ndata: {sequence}\n\n")
        try output.flush()
        sequence += 1
        sleep(1.seconds)

    return ok(())

def echo(socket: WebSocket) -> Result[Unit, WebSocketError]:
    while True:
        let message = try socket.receive()
        if message.is_none(): return ok(())

        try socket.send_bytes(message.get().data, message.get().text)

    return ok(())

def application(server: Server) -> Result[Unit, HttpError]:
    let environment = control().environment()
    if environment.is_error(): return error(HttpError.InvalidInput)

    let configured = environment.get().get("API_TOKEN")
    if configured.is_none() or configured.get().byte_length() < 16: return error(
        HttpError.InvalidInput
    )

    let token = configured.get().clone()
    let member = server.member_index + 0
    let lifecycle = server.clone()
    let observations = server.clone()
    var api = Router()
    api.use(lambda request, next: authenticated(request, next, token))
    api.post("/greeting", lambda request: greet(request, member))
    api.get(
        "/events",
        lambda request: stream_response(
            lambda (var output: WriteStream): events(var output), "text/event-stream"
        )
    )
    api.get(
        "/socket", lambda request: websocket_response(echo, max_message_bytes: 1048576)
    )
    api.get("/stats", lambda request: json_response(lifecycle.stats()).get().clone())

    let readiness = server.clone()
    var routes = Router()
    routes.use(safety_headers)
    routes.get("/health", lambda request: text_response("ok"))
    routes.get(
        "/ready",
        lambda request: text_response(
            "ready" if readiness.is_ready() else "draining",
            200 if readiness.is_ready() else 503
        )
    )
    routes.get(
        "/",
        lambda request: (
            html_response(
                Html.Element(
                    "main",
                    Map[String, String](),
                    [
                        Html.Element(
                            "h1",
                            Map[String, String](),
                            [
                                Html.Text(
                                    "Manuscript HTTP server"
                                )
                            ]
                        ),
                        Html.Element(
                            "p",
                            Map[String, String](),
                            [
                                Html.Text(
                                    "JSON, SSE and WebSocket routes share one scoped server."
                                )
                            ]
                        )
                    ]
                )
            )
            .get()
            .clone()
        )
    )
    routes.mount("/api", api)

    # Transport owns a bounded event ring. A stalled logger cannot block request completion.
    with TaskGroup[Result[Unit, LogError]]() as tasks:
        let observer = tasks.spawn(
            lambda channel:
                with try create(stdout_transport(), max_bytes: 16384) as logger:
                    while True:
                        for event in observations.take_events(): try record(
                            logger, LogLevel.Info, "http", event
                        )
                        sleep(100.milliseconds)

                return ok(())
        )

        return server.run(routes)

    return ok(())

export def main() -> Int:
    let args = arguments()
    let mode = args.get(0, "local")
    let count = args.get(1, "4").parse_int().get(4)
    let address = args.get(2, "127.0.0.1:8080").clone()
    let options = HttpServerOptions(
        event_capacity: 1024, max_requests: 128, max_connections: 1024,
        max_body_bytes: 1048576, max_response_bytes: 8388608, max_header_bytes: 32768,
        timeout: 30.seconds, header_timeout: 5.seconds, idle_timeout: 15.seconds,
        write_timeout: 10.seconds, grace: 10.seconds
    )

    if mode == "workers": serve(address, application, options, workers(count)).get()
    elif mode == "processes": serve(address, application, options, processes(count)).get()
    else: serve(address, application, options).get()

    return 0
