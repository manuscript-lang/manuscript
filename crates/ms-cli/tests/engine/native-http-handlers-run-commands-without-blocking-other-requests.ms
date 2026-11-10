import buffered, headers, HttpRequest, HttpResponse from "@std/net/http.ms"
import serve from "@std/net/net.ms"
import stdout from "@std/io/io.ms"
import run from "@std/os/process.ms"

fn handle(request: HttpRequest) HttpResponse:
    if request.path == "/slow":
        print("started")

        let _flushed = stdout().flush()
        let _out = run("sleep", ["0.5"]).wait()

    return HttpResponse(200, headers(), request.path.to_bytes())

export fn main() Int:
    if let acquired = serve(address: "127.0.0.1:0", handler: buffered(handle)):
        let server = acquired
        print("{server.address()}")

        let _flushed = stdout().flush()
        let _ignored = server.wait()
        return 0

    return 1
