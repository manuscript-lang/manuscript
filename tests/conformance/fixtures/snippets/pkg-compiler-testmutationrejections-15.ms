# conform: tags=aliasing,diagnostics,modules,stdlib-net,tier-io
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:36 TestMutationRejections
from "@std/net.ms" import Connection

def f(socket: Connection) -> Unit:
    socket.clone()
