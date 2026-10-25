from "@std/http.ms" import Server, Router, Request, Response, HttpError, HttpServerOptions, serve, workers, processes, text_response, json_response
from "@std/process.ms" import arguments, control
from "@std/time.ms" import sleep

extern def msrt_task_count() -> Int

type Sample:
    member: Int
    active_requests: Int
    active_connections: Int
    tasks: Int
    heap_used: Int
    external: Int

def cpu(request: Request, member: Int) -> Response:
    var value = 17
    var index = 0

    while index < 100000:
        value = (value * 31 + index) % 1000000007
        index += 1

    return text_response(f"{member}:{value}")

def application(server: Server) -> Result[Unit, HttpError]:
    let member = server.member_index + 0
    let observed = server.clone()
    var routes = Router()
    routes.get("/", lambda request: text_response(f"{member}"))
    routes.get("/cpu", lambda request: cpu(request, member))

    routes.get(
        "/slow",
        lambda request:
            sleep(20.milliseconds)
            return text_response(f"{member}")
    )

    routes.get(
        "/overload",
        lambda request:
            sleep(100.milliseconds)
            return text_response(f"{member}")
    )

    routes.get(
        "/deadline",
        lambda request:
            sleep(5.seconds)
            return text_response("late")
    )

    routes.get(
        "/stats",
        lambda request:
            let stats = observed.stats()
            let memory = control().memory_usage().get()
            return (
                json_response(
                    Sample(
                        member, stats.active_requests, stats.active_connections,
                        msrt_task_count(), memory.heap_used, memory.external
                    )
                )
                .get()
                .clone()
            )
    )

    return server.run(routes)

export def main() -> Int:
    let args = arguments()
    let mode = args.get(0, "local")
    let count = args.get(1, "1").parse_int().get()
    let address = args.get(2, "127.0.0.1:19743").clone()
    let options = HttpServerOptions(
        max_requests: 64, max_connections: 256, max_body_bytes: 1048576,
        max_response_bytes: 1048576, timeout: 2.seconds, header_timeout: 1.seconds,
        idle_timeout: 1.seconds, write_timeout: 1.seconds, grace: 2.seconds
    )

    if mode == "workers": serve(address, application, options, workers(count)).get()
    elif mode == "processes": serve(address, application, options, processes(count)).get()
    else: serve(address, application, options).get()

    return 0
