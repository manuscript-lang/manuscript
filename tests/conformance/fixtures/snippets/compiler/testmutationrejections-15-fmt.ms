# conform: tags=aliasing,formatter,modules,parser,stdlib-net,tier-io
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:36 TestMutationRejections
import Connection from "@std/net/net.ms"

fn f(socket: Connection) Unit:
    socket.clone()
