# Benchmark server: main <port> <data-dir> [threads]. With threads above 1, that many workers each serve the port from one shared listener. The Go server in ../go answers the same requests.
from "@std/bytes.ms" import Bytes
from "@std/fs.ms" import filesystem
from "@std/collections.ms" import range
from "@std/http.ms" import headers, HttpRequest, HttpResponse, HttpServerOptions, buffered
from "@std/net.ms" import network
from "@std/process.ms" import arguments
from "@std/workers.ms" import Worker, WorkerGroup, worker_channel

def score(id: Int) -> Int:
    return id * 7919 % 1000

def reply(status: Int, text: String) -> HttpResponse:
    return HttpResponse(status, headers(), text.to_bytes())

# Next entry after (prev_id, prev_score) in score-descending, id-ascending order.
def pick_after(prev_id: Int, prev_score: Int) -> Int:
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

def top(k: Int) -> String:
    var out = "["
    var n = 0
    var prev_id = -1
    var prev_score = 1000

    while n < k:
        let best = pick_after(prev_id, prev_score)
        if n > 0:
            out = f"{out},"
        out = f"{out}\{\"id\":{best},\"score\":{score(best)}\}"
        prev_id = best
        prev_score = score(best)
        n += 1

    return f"{out}]\n"

def top_reply(query: String) -> HttpResponse:
    let parts = query.split("=")
    if parts.length() != 2 or parts.get(0) != "n":
        return reply(400, "bad n\n")

    if let k = parts.get(1).parse_int():
        if k >= 1 and k <= 50:
            return reply(200, top(k))
    return reply(400, "bad n\n")

def user_reply(path: String) -> HttpResponse:
    let parts = path.split("/")
    if parts.length() != 3:
        return reply(404, "not found\n")

    if let id = parts.get(2).parse_int():
        if id >= 0 and id < 1000:
            return reply(
                200, f"\{\"id\":{id},\"name\":\"user{id}\",\"score\":{score(id)}\}\n"
            )
    return reply(404, "not found\n")

# Resolve localhost, write 1 MiB to the connection's own file, read it back.
def io_reply(dir: String, slot: String, payload: Bytes) -> HttpResponse:
    if let addresses = network().lookup("localhost"):
        let path = f"{dir}/m{slot}.bin"
        if let got = write_and_read(path, payload):
            return reply(200, f"{addresses.length()} {got.length()}\n")

        return reply(500, "file failed\n")

    return reply(500, "lookup failed\n")

def write_and_read(path: String, payload: Bytes) -> Result[Bytes, Error]:
    let fs = filesystem()
    try fs.write_file_bytes(path, payload, replace: True)
    return ok(try fs.read_file(path))

# Serves the benchmark endpoints on 127.0.0.1:<port> until the server stops.
def serve_here(port: String, dir: String, ready: Bool) -> Int:
    var text = "0123456789abcdef"
    var i = 0

    while i < 16:
        text = f"{text}{text}"
        i += 1

    let payload = text.to_bytes()
    let dir_copy = dir.clone()

    let handler = lambda (request: HttpRequest) -> HttpResponse:
        if request.path == "/health":
            return reply(200, "ok\n")
        if request.path == "/top":
            return top_reply(request.query)
        if request.path == "/io":
            return io_reply(dir_copy, request.query, payload)
        if request.path.starts_with("/user/"):
            return user_reply(request.path)

        return reply(404, "not found\n")

    let options = HttpServerOptions(shared: True)

    if let acquired = network().serve(
        address: f"127.0.0.1:{port}", handler: buffered(handler), options: options
    ):
        with let server = acquired:
            if ready:
                var ch = worker_channel[Int, Int]()
                ch.send(1)

            let _ignored = server.wait()
            return 0

    return 1

# One serving thread of a multi-threaded run; the starter waits for its signal that the port is open.
def serve_worker() -> Unit:
    let args = arguments()
    let _code = serve_here(args.get(0), args.get(1), True)

export def main() -> Int:
    let args = arguments()
    if args.length() < 2 or args.length() > 3:
        return 2

    var threads = 1
    if args.length() == 3:
        threads = args.get(2).parse_int().get(1)
    if threads <= 1:
        return serve_here(args.get(0), args.get(1), False)

    with let group = WorkerGroup[Int, Int]():
        var workers: List[Worker[Int, Int]] = []

        for i in range(0, threads):
            var worker = group.spawn(serve_worker).get(none)
            let _ready = worker.channel.receive()
            workers.append(worker)

        let _stopped = workers[0].join()

    return 0
