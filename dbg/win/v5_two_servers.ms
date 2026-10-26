from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import stdout
from "@std/net.ms" import network
from "@std/time.ms" import nanoseconds, sleep

def handle(request: HttpRequest) -> HttpResponse:
    if request.path == "/slow":
        sleep(nanoseconds(3000000000))
    return HttpResponse(200, headers(), f"ok {request.path}\n".to_bytes())

def say(text: String) -> Unit:
    let _w = stdout().write(f"{text}\n")

def fetch(address: String, path: String) -> String:
    say("connect")
    if let conn = network().connect(address):
        say("connected")
        let _sent = conn.write(f"GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        say("sent")
        var text = ""

        while True:
            if let chunk = conn.read(timeout: nanoseconds(5000000000)):
                if let data = chunk:
                    text = f"{text}{data.decode_utf8().get("?")}"
                    say(f"read {data.length()}")
                    continue

            break

        conn.close()
        return text

    return "connect failed"

def one(label: String, grace_ms: Int, path: String) -> Bool:
    say(f"{label} start")
    let options = HttpServerOptions(timeout: nanoseconds(200000000), grace: nanoseconds(grace_ms * 1000000))
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle), options: options):
        with let server = acquired:
            say(f"{label} serving")
            let r = fetch(server.address(), path)
            say(f"{label} got: {r.length()} {r.starts_with("HTTP/1.1 504")} {r.starts_with("HTTP/1.1 200")}")
            server.close()
            say(f"{label} closed")
            return True
    return False

export def main() -> Int:
    if one("a", 0, "/slow"):
        if one("b", 500, "/slow"):
            return 0
    return 1
