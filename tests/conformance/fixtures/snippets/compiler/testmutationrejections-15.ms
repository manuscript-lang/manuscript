# conform: tags=aliasing,diagnostics,modules,stdlib-net,tier-io
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:36 TestMutationRejections
import Connection from "@std/net/net.ms"

fn f(socket: Connection) Unit:
    socket.clone()
