// conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-io,stdlib-queues,tier-stdlib
// conform: phase=parse
// conform: origin=pkg/compiler/mutation_test.go:11 TestMutationRejections
import stdout from "@std/io/io.ms"
import FileHandle from "@std/os/fs.ms"
import Queue from "@std/collections/queue.ms"

interface Read:
    fn get() Int

type Val:
    val: Int

fn Val.get() Int:
    return self.val
