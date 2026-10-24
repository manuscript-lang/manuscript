# conform: tags=formatter,modules,parser,records,stdlib-io,stdlib-net,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/mutation_test.go:16 TestMutationCLIRejectsInvalidAssignmentsAndHandleClones
from "@std/io.ms" import File
from "@std/net.ms" import Connection

type Val:
    val: Int
