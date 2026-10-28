import {buffered, headers, HttpRequest, HttpResponse} from "@std/http.ms"
import network from "@std/net.ms"
import stdout from "@std/io.ms"
import commands from "@std/process.ms"

fn handle(request: HttpRequest) HttpResponse:
    if request.path == "/slow":
        let _out = commands().run("sleep", ["0.5"])
    return HttpResponse(200, headers(), request.path.to_bytes())

export fn main() Int:
    if let acquired = network().serve(address: "127.0.0.1:0", handler: buffered(handle)):
        with let server = acquired:
            stdout().write("{server.address()}\n").get()
            stdout().flush().get()

            let _ignored = server.wait()
            return 0

    return 1
