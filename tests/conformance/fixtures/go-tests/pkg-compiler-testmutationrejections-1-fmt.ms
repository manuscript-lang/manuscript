# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-io,stdlib-queues,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/mutation_test.go:11 TestMutationRejections
import stdout from "@std/io.ms"
import File from "@std/io.ms"
import Queue from "@std/queues.ms"
interface Read:
    fn get() Int
type Val:
    val: Int
impl Read for Val:
    fn get() Int:
        return self.val
