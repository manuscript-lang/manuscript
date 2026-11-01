# conform: tags=diagnostics,modules,stdlib-queues,testing,tier-stdlib
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:447 TestServiceBoundaries
import Queue from "@std/collections/queue.ms"

test "opaque":
    var queue = Queue[Int](capacity: 1)
    let _capacity = queue.capacity
