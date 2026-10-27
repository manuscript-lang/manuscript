from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import stderr
from "@std/net.ms" import network
from "@std/time.ms" import nanoseconds, sleep

def log(text: String) -> Unit:
    let _w = stderr().write(f"{text}\n")

def handle(request: HttpRequest) -> HttpResponse:
    log(f"handler {request.path}")
    if request.path == "/slow":
        sleep(nanoseconds(3000000000))
        log("handler woke")
    return HttpResponse(200, headers(), f"ok {request.path}\n".to_bytes())

def fetch(address: String, path: String) -> String:
    log(f"connect {path}")
    if let conn = network().connect(address):
        log("connected")
        let _sent = conn.write(f"GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        log("sent")
        var text = ""
        while True:
            if let chunk = conn.read(timeout: nanoseconds(5000000000)):
                if let data = chunk:
                    text = f"{text}{data.decode_utf8().get("?")}"
                    log(f"chunk {text.length()}")
                    continue

            break

        log("read done")
        conn.close()
        return text

    return "connect failed"

export def main() -> Int:
    log("start")
    let options = HttpServerOptions(timeout: nanoseconds(200000000), grace: nanoseconds(0))
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle), options: options):
        log("served")
        with let server = acquired:
            log("in with")
            let slow = fetch(server.address(), "/slow")
            log(f"slow: {slow.starts_with("HTTP/1.1 504")}")
            let fast = fetch(server.address(), "/fast")
            log(f"fast: {fast.starts_with("HTTP/1.1 200 OK")}")
            server.close()
            log("closed")
        log("after with")
        return 0
    return 1
