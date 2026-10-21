# conform: tags=modules,parser,stdlib-queues,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:135 TestTypedCompletionWhileEditing
import Queue from "@std/collections.ms"
fn read(queue: Queue[Int]) Unit:
    queue.|
