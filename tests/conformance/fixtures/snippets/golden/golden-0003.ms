// conform: tags=diagnostics
// conform: phase=check
import network from "@std/net/net.ms"
import HttpResponse from "@std/net/http.ms"
import panic from "@std/faults.ms"
fn use() Unit:
    shared := Map[Int, Int]()
    _server := network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        shared.add(key: 1, value: 2)
        return panic("unreached")
    )
