// Benchmark server: main <port> <data-dir> [threads]. `serve` places each connection on one of that many scheduler threads. The Go server in ../go answers the same requests.
import Bytes from "@std/bytes.ms"
import read_file, write_file from "@std/os/fs.ms"
import (
    HttpServerOptions,
    headers,
    HttpExchange,
    HttpRequest,
    HttpResponse,
    buffered
) from "@std/net/http.ms"
import lookup, serve from "@std/net/net.ms"
import max from "@std/math/math.ms"
import arguments from "@std/os/env.ms"

fn score(id: Int) Int:
    return id * 7919 % 1000

fn reply(status: Int, text: String) HttpResponse:
    return HttpResponse(status, headers(), text.to_bytes())

// Next entry after (prev_id, prev_score) in score-descending, id-ascending order.
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

// Resolve localhost, write 1 MiB to the connection's own file, read it back.
fn io_reply(dir: String, slot: String, payload: Bytes) HttpResponse:
    if let addresses = lookup("localhost"):
        let path = "{dir}/m{slot}.bin"
        if let got = write_and_read(path, payload):
            return reply(200, "{addresses.length()} {got.length()}\n")

        return reply(500, "file failed\n")

    return reply(500, "lookup failed\n")

fn write_and_read(path: String, payload: Bytes) Result[Bytes, Error]:
    try write_file(path, payload, replace: true).wait()
    return ok(try read_file(path).wait())

// The benchmark endpoints.
fn make_handler(dir: String) fn(var HttpExchange) Result[Unit, Error]:
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

// Serves the benchmark endpoints on 127.0.0.1:<port> on `threads` scheduler threads until the server stops.
fn serve_here(port: String, dir: String, threads: Int) Int:
    let options = HttpServerOptions(cores: threads)

    if let acquired = serve(
        address: "127.0.0.1:{port}", handler: make_handler(dir), options: options
    ):
        let server = acquired
        let _ignored = server.wait()
        return 0

    return 1

export fn main() Int:
    let args = arguments()
    if args.length() < 2 or args.length() > 3:
        return 2

    var threads = 1
    if args.length() == 3:
        threads = args.get(2).parse_int().get(1)
    return serve_here(args.get(0), args.get(1), max(threads, 1))
