# conform: tags=diagnostics,modules,records,stdlib-io,stdlib-net,tier-io
# conform: phase=check
# conform: origin=tests/e2e/mutation_test.go:16 TestMutationCLIRejectsInvalidAssignmentsAndHandleClones
import File from "@std/io.ms"
import Connection from "@std/net.ms"
type Val:
    val: Int
