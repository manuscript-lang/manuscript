# conform: tags=aliasing,formatter,modules,parser,stdlib-net,tier-io
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:36 TestMutationRejections
from "@std/net.ms" import Connection

def f(socket: Connection) -> Unit:
    socket.clone()
