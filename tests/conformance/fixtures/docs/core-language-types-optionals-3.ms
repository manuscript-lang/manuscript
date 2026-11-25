// conform: tags=diagnostics,formatter,modules,stdlib-queue,tier-stdlib
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/optionals.md:32
import Queue from "@std/collections/queue.ms"

fn main() Void {
	var _bounded = Queue[Int](capacity: 4)
	var _unbounded = Queue[Int]()
}
// expect-exit: 0
