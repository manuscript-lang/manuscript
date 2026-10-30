import {HttpRequest, HttpResponse, buffered, headers} from "@std/http.ms"
import {Listener, NetworkError, deal_connections, network, serve_core} from "@std/net.ms"
import {Worker, WorkerGroup} from "@std/workers.ms"
import {TaskGroup} from "@std/tasks.ms"
import {expect_true} from "@std/test.ms"

fn core() Unit:
    let tag = "hello"
    let handler = fn(request: HttpRequest) HttpResponse:
        return HttpResponse(status: 200, headers: headers(), body: tag.to_bytes())
    let served = serve_core(buffered(handler))
    let _ = served

fn run(listener: Listener, workers: List[Worker[Int, Int]]) Result[Unit, NetworkError]:
    return deal_connections(listener, workers)

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

test "deal_connections serves clients and fails when a worker ends":
    let net = network()
    let listener = try net.listen("127.0.0.1:0")
    let address = listener.address()
    let cores = WorkerGroup[Int, Int]()
    var workers: List[Worker[Int, Int]] = []
    var kept: List[Worker[Int, Int]] = []

    for i in 0..3:
        var worker = try cores.spawn(core)
        kept.append(worker.clone())
        workers.append(worker)

    let group = TaskGroup[Result[Unit, NetworkError]]()
    let serving = group.spawn(fn ch: run(listener, workers))

    for i in 0..5:
        let text = get(address)
        try expect_true(text.starts_with("HTTP/1.1 200 OK"))
        try expect_true(text.ends_with("hello"))

    for i in 0..3:
        kept[i].channel.close()

    # The next connection is dealt to a worker whose channel is closed.
    let _ = get(address)
    let outcome = try serving.result()
    try expect_true(outcome.is_error())
