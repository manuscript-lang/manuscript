// conform: tags=control-flow,diagnostics,formatter,interfaces,modules,records,stdlib-io,stdlib-queues,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/compiler/mutation_test.go:11 TestMutationRejections
import (
	Queue from "@std/collections/queue.ms",
	stdout from "@std/io/io.ms",
	FileHandle from "@std/os/fs.ms",
)

interface Read {
	fn get() Int
}

type Val {
	val Int
}

fn Val.get() Int {
	return self.val
}
// expect-exit: 0
