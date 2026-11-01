import (
    HttpExchange,
    HttpError,
    HttpRequest,
    HttpResponse,
    buffered,
    headers
) from "@std/net/http.ms"
import Connection, connect, listen, serve_connections from "@std/net/net.ms"
import expect_equal, expect_ok, expect_true from "@std/test/test.ms"
import Worker, WorkerGroup, worker_channel from "@std/concurrency/workers.ms"

fn answer(id: Int) fn(var HttpExchange) Unit!HttpError:
    let handler = fn(request: HttpRequest) HttpResponse:
        return HttpResponse(
            status: 200, headers: headers(), body: "worker {id}".to_bytes()
        )
    return buffered(handler)

# A serving worker: adopts the socket handles its starter sends until the channel ends.
fn serves_handed() Unit:
    var ch = worker_channel[Int, Int]()
    let id = ch.receive().get(none).get(0)

    if let acquired = serve_connections(handler: answer(id)):
        var server = acquired

        while true:
            if let connection = ch.receive().get(none):
                server.adopt(connection)
                continue

            break

        server.close().get(none)

test "an acceptor deals connections round robin to serving workers":
    let listener = try listen("127.0.0.1:0")
    var group = WorkerGroup[Int, Int]()
    var workers: List[Worker[Int, Int]] = []

    for i in 0..3:
        var worker = try group.spawn(serves_handed)
        try expect_ok(worker.channel.send(i))
        workers.append(worker)

    # Clients connect and send their request first; the backlog holds them until accepted.
    var clients: List[Connection] = []

    for i in 0..6:
        var client = try connect(listener.address(), 2.seconds)
        try client.write("GET /x HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        clients.append(client)

    for i in 0..6:
        let handle = try listener.accept_raw(2.seconds)
        try expect_ok(workers[i % 3].channel.send(handle))

    for i in 0..6:
        var answer_bytes = ""

        while true:
            let chunk = try clients[i].read(none, 2.seconds)

            if let data = chunk:
                answer_bytes = "{answer_bytes}{data.decode_utf8().get("")}"
                continue

            break

        try expect_true(answer_bytes.starts_with("HTTP/1.1 200 OK"))
        try expect_true(answer_bytes.ends_with("worker {i % 3}"))

    for i in 0..3:
        workers[i].channel.close()
