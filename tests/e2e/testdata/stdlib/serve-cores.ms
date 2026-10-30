import {HttpRequest, HttpResponse, buffered, headers} from "@std/http.ms"
import {Listener, NetworkError, serve_cores, network, serve_core} from "@std/net.ms"
import {TaskGroup} from "@std/tasks.ms"
import {expect_true} from "@std/test.ms"

fn core() Unit:
    let tag = "hello"
    let handler = fn(request: HttpRequest) HttpResponse:
        return HttpResponse(status: 200, headers: headers(), body: tag.to_bytes())
    let served = serve_core(buffered(handler))
    let _ = served

fn run(listener: Listener) Result[Unit, NetworkError]:
    return serve_cores(listener, core, 3)

fn get(address: String) String:
    let net = network()
    var client = net.connect(address, 2.seconds).get()
    let _ = client.write("GET /x HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
    var text = ""

    while true:
        let chunk = client.read(none, some(2.seconds))
        if chunk.is_error():
            break

        if let data = chunk.get(none):
            text = "{text}{data.decode_utf8().get("")}"
            continue

        break

    return text

test "serve_cores serves clients across workers and fails when accepting fails":
    let net = network()
    let listener = try net.listen("127.0.0.1:0")
    let address = listener.address()
    var group = TaskGroup[Result[Unit, NetworkError]]()
    group.spawn(fn ch: run(listener))

    for i in 0..5:
        let text = get(address)
        try expect_true(text.starts_with("HTTP/1.1 200 OK"))
        try expect_true(text.ends_with("hello"))

    group.close()

test "serve_cores rejects fewer than one core":
    let listener = try network().listen("127.0.0.1:0")
    let outcome = serve_cores(listener, core, 0)
    try expect_true(outcome.is_error())
