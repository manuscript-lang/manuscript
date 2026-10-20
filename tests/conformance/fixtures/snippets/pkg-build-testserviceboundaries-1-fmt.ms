# conform: tags=formatter,modules,parser,stdlib-queues,testing,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:447 TestServiceBoundaries
import Queue from "@std/queues.ms"
test "opaque":
    let queue = Queue[Int](capacity: 1)
    let capacity = queue.capacity
