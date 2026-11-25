// conform: tags=diagnostics,modules,records,stdlib-io,stdlib-net,tier-io
// conform: phase=check
// conform: origin=tests/e2e/mutation_test.go:16 TestMutationCLIRejectsInvalidAssignmentsAndHandleClones
import (
	Connection from "@std/net/net.ms",
	FileHandle from "@std/os/fs.ms",
)

type Val {
	val Int
}
// expect-exit: 0
