// conform: tags=diagnostics
// conform: phase=check
import Network from "@std/net/net.ms"
fn f(socket: Network) Unit:
    socket.clone()
