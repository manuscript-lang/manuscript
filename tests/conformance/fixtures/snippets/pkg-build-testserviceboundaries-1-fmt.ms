# conform: tags=formatter,modules,parser,stdlib-queues,testing,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:447 TestServiceBoundaries
from "@std/queue.ms" import Queue

test "opaque":
    var queue = Queue[Int](capacity: 1)
    let _capacity = queue.capacity
