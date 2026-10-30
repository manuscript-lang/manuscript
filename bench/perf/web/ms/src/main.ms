# Benchmark server: main <port> <data-dir> [threads]. With threads above 1 the main thread accepts and hands each connection, round robin, to one of that many serving workers. The Go server in ../go answers the same requests.
import Bytes from "@std/bytes.ms"
import filesystem from "@std/fs.ms"
import {headers, HttpError, HttpExchange, HttpRequest, HttpResponse, buffered} from "@std/http.ms"
import {deal_connections, network, serve_core} from "@std/net.ms"
import arguments from "@std/process.ms"
import {Worker, WorkerGroup} from "@std/workers.ms"

fn score(id: Int) Int:
    return id * 7919 % 1000

fn reply(status: Int, text: String) HttpResponse:
    return HttpResponse(status, headers(), text.to_bytes())

# Next entry after (prev_id, prev_score) in score-descending, id-ascending order.
fn pick_after(prev_id: Int, prev_score: Int) Int:
    var best = -1
    var best_score = -1
    var id = 0

    while id < 1000:
        let sc = score(id)

        if sc < prev_score or (sc == prev_score and id > prev_id):
            if sc > best_score:
                best = id
                best_score = sc

        id += 1

    return best

fn top(k: Int) String:
    var out = "["
    var n = 0
    var prev_id = -1
    var prev_score = 1000

    while n < k:
        let best = pick_after(prev_id, prev_score)
        if n > 0:
            out = "{out},"
        out = "{out}\{\"id\":{best},\"score\":{score(best)}\}"
        prev_id = best
        prev_score = score(best)
        n += 1

    return "{out}]\n"

fn top_reply(query: String) HttpResponse:
    let parts = query.split("=")
    if parts.length() != 2 or parts.get(0) != "n":
        return reply(400, "bad n\n")

    if let k = parts.get(1).parse_int():
        if k >= 1 and k <= 50:
            return reply(200, top(k))
    return reply(400, "bad n\n")

fn user_reply(path: String) HttpResponse:
    let parts = path.split("/")
    if parts.length() != 3:
        return reply(404, "not found\n")

    if let id = parts.get(2).parse_int():
        if id >= 0 and id < 1000:
            return reply(
                200, "\{\"id\":{id},\"name\":\"user{id}\",\"score\":{score(id)}\}\n"
            )
    return reply(404, "not found\n")

# Resolve localhost, write 1 MiB to the connection's own file, read it back.
fn io_reply(dir: String, slot: String, payload: Bytes) HttpResponse:
    if let addresses = network().lookup("localhost"):
        let path = "{dir}/m{slot}.bin"
        if let got = write_and_read(path, payload):
            return reply(200, "{addresses.length()} {got.length()}\n")

        return reply(500, "file failed\n")

    return reply(500, "lookup failed\n")

fn write_and_read(path: String, payload: Bytes) Result[Bytes, Error]:
    let fs = filesystem()
    try fs.write_file_bytes(path, payload, replace: true)
    return ok(try fs.read_file(path))

# The benchmark endpoints.
fn make_handler(dir: String) fn(HttpExchange) Result[Unit, HttpError]:
    var text = "0123456789abcdef"
    var i = 0

    while i < 16:
        text = "{text}{text}"
        i += 1

    let payload = text.to_bytes()
    let dir_copy = dir.clone()

    let handler = fn(request: HttpRequest) HttpResponse:
        if request.path == "/health":
            return reply(200, "ok\n")
        if request.path == "/top":
            return top_reply(request.query)
        if request.path == "/io":
            return io_reply(dir_copy, request.query, payload)
        if request.path.starts_with("/user/"):
            return user_reply(request.path)

        return reply(404, "not found\n")

    return buffered(handler)

# Serves the benchmark endpoints on 127.0.0.1:<port> until the server stops.
fn serve_here(port: String, dir: String) Int:
    if let acquired = network().serve(
        address: "127.0.0.1:{port}", handler: make_handler(dir)
    ):
        let server = acquired
        let _ignored = server.wait()
        return 0

    return 1

# One serving thread of a multi-threaded run: serves the connections its starter sends.
fn serve_worker() Unit:
    let args = arguments()
    let _ = serve_core(make_handler(args.get(1)))

# Accepts on the main thread and deals the connections to `threads` workers.
fn serve_threads(port: String, threads: Int) Int:
    let group = WorkerGroup[Int, Int]()
    var workers: List[Worker[Int, Int]] = []

    for i in 0..threads:
        let worker = group.spawn(serve_worker).get(none)
        workers.append(worker)

    if let bound = network().listen("127.0.0.1:{port}"):
        let _ = deal_connections(bound, workers)
    return 1

export fn main() Int:
    let args = arguments()
    if args.length() < 2 or args.length() > 3:
        return 2

    var threads = 1
    if args.length() == 3:
        threads = args.get(2).parse_int().get(1)
    if threads <= 1:
        return serve_here(args.get(0), args.get(1))

    return serve_threads(args.get(0), threads)
