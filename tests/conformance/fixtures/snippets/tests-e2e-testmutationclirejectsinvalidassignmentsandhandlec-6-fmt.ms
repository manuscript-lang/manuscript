# conform: tags=aliasing,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/mutation_test.go:26 TestMutationCLIRejectsInvalidAssignmentsAndHandleClones
def f(socket: Connection) -> Unit:
    socket.clone()
