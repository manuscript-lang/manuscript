// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"
test "opaque":
    queue := Queue[Int](capacity: 1)
    capacity := queue.capacity
