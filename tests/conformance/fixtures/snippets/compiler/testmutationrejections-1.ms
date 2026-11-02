# conform: tags=control-flow,diagnostics,interfaces,modules,records,stdlib-io,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:11 TestMutationRejections
import stdout from "@std/io/io.ms"
import File from "@std/io/io.ms"
import Queue from "@std/collections/queue.ms"

interface Read:
    fn get() Int

type Val:
    val: Int

impl Read for Val:
    fn get() Int:
        return self.val
