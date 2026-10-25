from "@std/http.ms" import Server, Router, Request, Response, HttpError, serve, text_response, json_response, decode_json, stream_response
from "@std/json.ms" import JsonLimits
from "@std/web.ms" import html
from "@std/io.ms" import WriteStream, IoError
from "@std/time.ms" import sleep
from "@std/process.ms" import arguments

type Input:
    name: String

type Message:
    message: String

def json_echo(request: Request) -> Response:
    let input = decode_json[Input](
        request, JsonLimits(max_bytes: 4096, max_depth: 8, max_values: 16)
    )
    if input.is_error(): return text_response("Invalid JSON", 400)

    return json_response(Message("Hello, " + input.get().name)).get().clone()

def events(var output: WriteStream) -> Result[Unit, IoError]:
    try output.write("data: one\n\n")
    try output.flush()
    sleep(10.milliseconds)
    return output.write("data: two\n\n")

def application(server: Server) -> Result[Unit, HttpError]:
    var routes = Router()

    routes.use(
        lambda request,
        next:
            let response = next(request)
            response.headers.append("X-Example", "reference".to_bytes()).get()
            return response
    )

    routes.get(
        "/hello/:name",
        lambda request: (
            json_response(
                Message("Hello, " + request.params.get("name").get())
            )
            .get()
            .clone()
        )
    )
    routes.post("/echo", json_echo)
    routes.get(
        "/events",
        lambda request: stream_response(
            lambda (var output: WriteStream): events(var output), "text/event-stream"
        )
    )
    routes.get("/", lambda request: html("<h1>Hello</h1>"))
    return server.run(routes)

export def main() -> Int:
    serve(arguments().get(0, "127.0.0.1:19805").clone(), application).get()
    return 0
