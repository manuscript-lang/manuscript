# conform: tags=control-flow,diagnostics,interfaces,modules,records,stdlib-io,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/mutation_test.go:11 TestMutationRejections
from "@std/io.ms" import stdout
from "@std/io.ms" import File
from "@std/queue.ms" import Queue

interface Read:
    def get() -> Int

type Val:
    val: Int

impl Read for Val:
    def get() -> Int:
        return self.val
