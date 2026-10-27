# conform: tags=stdlib-http,stdlib-net,tier-io
# conform: phase=run
# conform: timeout=30
# A handler that is still waiting when the server's request timeout passes is cancelled and the
# request is answered 504, with or without a grace period; the server keeps serving afterwards.
from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import stdout
from "@std/net.ms" import network
from "@std/process.ms" import control
from "@std/time.ms" import nanoseconds, sleep

def handle(request: HttpRequest) -> HttpResponse:
    if request.path == "/slow":
        let _m = stdout().write("handler start\n")
        sleep(nanoseconds(1))
    return HttpResponse(200, headers(), f"ok {request.path}\n".to_bytes())

def fetch(address: String, path: String) -> String:
    let _p = stdout().write(f"connect {path}\n")
    if let conn = network().connect(address):
        let _q = stdout().write("connected\n")
        let _sent = conn.write(f"GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        var text = ""
        let _r = stdout().write("sent\n")

        while True:
            if let chunk = conn.read(timeout: nanoseconds(5000000000)):
                if let data = chunk:
                    text = f"{text}{data.decode_utf8().get("?")}"
                    continue

            break

        let _s = stdout().write("read done\n")
        conn.close()
        return text

    return "connect failed"

def run(label: String, grace_ms: Int) -> Bool:
    let options = HttpServerOptions(
        timeout: nanoseconds(200000000), grace: nanoseconds(grace_ms * 1000000)
    )

    if let acquired = network().serve(
        address: "127.0.0.1:0", handler: buffered(handle), options: options
    ):
        with let server = acquired:
            let start = control().monotonic_time()
            let slow = fetch(server.address(), "/slow")
            let elapsed_ms = (control().monotonic_time() - start) / 1000000
            let fast = fetch(server.address(), "/fast")
            let _slow = stdout().write(
                f"{label} slow: {slow.starts_with("HTTP/1.1 504")} prompt: {elapsed_ms < 2000}\n"
            )
            let _fast = stdout().write(f"{label} fast: {fast.starts_with("HTTP/1.1 200 OK")}\n")
            server.close()
            return True

    return False

export def main() -> Int:
    if run("plain", 0):
        return 0

    return 1
