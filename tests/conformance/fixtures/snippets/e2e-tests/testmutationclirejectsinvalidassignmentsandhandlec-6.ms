// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/mutation_test.go:26 TestMutationCLIRejectsInvalidAssignmentsAndHandleClones
fn f(socket Connection) Void {
	socket.clone()
}
