# conform: tags=diagnostics,modules,stdlib-queue,tier-stdlib
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:32
import Queue from "@std/queue.ms"

fn main() Unit:
    var bounded = Queue[Int](capacity: 4)
    var unbounded = Queue[Int]()
