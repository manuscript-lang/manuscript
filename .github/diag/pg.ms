from "@std/collections.ms" import range
from "@std/fetch.ms" import fetch
from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse
from "@std/io.ms" import stderr
from "@std/net.ms" import network
from "@std/tasks.ms" import TaskGroup

def log(text: String) -> Unit:
    let _w = stderr().write(f"{text}\n")

def page(request: HttpRequest) -> HttpResponse:
    return HttpResponse(200, headers(), "x".repeat(65536).get("").to_bytes())

def get(address: String) -> Int:
    if let response = fetch(f"http://{address}/page"):
        return response.body.length()
    return -1

export def main() -> Int:
    log("start")
    let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(page)).get(none)
    with let server = acquired:
        log("served")
        log(f"one {get(server.address())}")
        for i in range(0, 3):
            log(f"seq {i} {get(server.address())}")
        let addr = server.address()
        with let tasks = TaskGroup[Int]():
            let a1 = addr.clone()
            let a = tasks.spawn(lambda c: get(a1))
            let a2 = addr.clone()
            let b = tasks.spawn(lambda c: get(a2))
            let a3 = addr.clone()
            let c2 = tasks.spawn(lambda c: get(a3))
            let a4 = addr.clone()
            let d = tasks.spawn(lambda c: get(a4))
            log("spawned")
            log(f"par {a.result().is_ok()} {b.result().is_ok()} {c2.result().is_ok()} {d.result().is_ok()}")
        server.close()
    log("done")
    return 0
