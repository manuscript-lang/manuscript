// conform: tags=aliasing,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/mutation_test.go:26 TestMutationCLIRejectsInvalidAssignmentsAndHandleClones
fn f(socket Connection) Void {
	socket.clone()
}
// expect-error: MS2001 4:13 unknown type Connection; add: import Connection from "@std/net/net.ms"
// expect-fix: 1:1-1:1 "import Connection from \"@std/net/net.ms\"\n"
