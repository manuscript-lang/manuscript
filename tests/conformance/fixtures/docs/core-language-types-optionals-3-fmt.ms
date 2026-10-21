# conform: tags=formatter,modules,parser,stdlib-queues,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:32
import Queue from "@std/collections.ms"

let bounded = Queue[Int](capacity: 4)
let unbounded = Queue[Int]()
