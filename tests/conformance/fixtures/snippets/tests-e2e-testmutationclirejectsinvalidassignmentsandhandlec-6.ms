# conform: tags=aliasing,diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/mutation_test.go:26 TestMutationCLIRejectsInvalidAssignmentsAndHandleClones
fn f(socket: Connection) Unit:
    socket.clone()
