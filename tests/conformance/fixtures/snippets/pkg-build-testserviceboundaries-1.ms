# conform: tags=diagnostics,modules,stdlib-queues,testing,tier-stdlib
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:447 TestServiceBoundaries
import Queue from "@std/collections.ms"
test "opaque":
    let queue = Queue[Int](capacity: 1)
    let capacity = queue.capacity
