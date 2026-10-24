# Benchmark server: main <port> <data-dir>. The Go server in ../go answers the same requests.
from "@std/bytes.ms" import Bytes
from "@std/fs.ms" import filesystem
from "@std/http.ms" import headers, HttpRequest, HttpResponse
from "@std/net.ms" import network
from "@std/process.ms" import arguments

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

export def main() -> Int:
    let args = arguments()
    if args.length() != 2:
        return 2

    let dir = args.get(1)
    var text = "0123456789abcdef"
    var i = 0

    while i < 16:
        text = f"{text}{text}"
        i += 1

    let payload = text.to_bytes()

    let handler = lambda (request: HttpRequest) -> HttpResponse:
        if request.path == "/health":
            return reply(200, "ok\n")
        if request.path == "/top":
            return top_reply(request.query)
        if request.path == "/io":
            return io_reply(dir, request.query, payload)
        if request.path.starts_with("/user/"):
            return user_reply(request.path)

        return reply(404, "not found\n")

    if let acquired = network().serve(
        address: f"127.0.0.1:{args.get(0)}", handler: handler
    ):
        with acquired as server:
            let _ignored = server.wait()
            return 0

    return 1
