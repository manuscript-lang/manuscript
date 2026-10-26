from "@std/http.ms" import buffered, headers, HttpRequest, HttpResponse, HttpServerOptions
from "@std/io.ms" import stdout
from "@std/fs.ms" import filesystem
from "@std/net.ms" import network
from "@std/time.ms" import nanoseconds, sleep

def handle(request: HttpRequest) -> HttpResponse:
    if request.path == "/slow":
        sleep(nanoseconds(3000000000))
    return HttpResponse(200, headers(), f"ok {request.path}\n".to_bytes())

def say(text: String) -> Unit:
    let _w = filesystem().append_file("trace.txt", f"{text}\n")

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

def one(label: String) -> Bool:
    say(f"{label} start")
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        with let server = acquired:
            say(f"{label} serving")
            server.close()
            say(f"{label} closed")
            return True
    return False

export def main() -> Int:
    if one("a"):
        if one("b"):
            say("done")
            return 0
    return 1
