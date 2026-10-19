# conform: tags=diagnostics,modules,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:32
import Queue from "@std/queues.ms"

let bounded = Queue[Int](capacity: 4)
let unbounded = Queue[Int]()
