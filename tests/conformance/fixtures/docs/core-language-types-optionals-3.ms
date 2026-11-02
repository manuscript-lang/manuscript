# conform: tags=diagnostics,modules,stdlib-queue,tier-stdlib
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:32
import Queue from "@std/collections/queue.ms"

fn main() Unit:
    var _bounded = Queue[Int](capacity: 4)
    var _unbounded = Queue[Int]()
