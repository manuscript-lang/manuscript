// conform: tags=diagnostics
// conform: phase=check
import network from "@std/net/net.ms"
import HttpResponse, HttpServerOptions from "@std/net/http.ms"
import panic from "@std/faults.ms"
fn run() Unit:
    values := [0]
