# conform: tags=formatter,modules,parser,stdlib-queue,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:32
import Queue from "@std/queue.ms"

fn main() Unit:
    var _bounded = Queue[Int](capacity: 4)
    var _unbounded = Queue[Int]()
