# conform: tags=modules,parser,stdlib-queues,strings,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:238 TestUniversalToStringCompletion
import Queue from "@std/queues.ms"
fn text(value: Queue[Int]) String:
    return value.|
