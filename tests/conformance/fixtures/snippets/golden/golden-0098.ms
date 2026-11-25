// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"

test "opaque" {
	queue := Queue[Int](capacity: 1)
	capacity := queue.capacity
}
// expect-error: MS2002 3:8-3:13 unknown standard module @std/queues.ms; did you mean '@std/collections/queue.ms'?
// expect-error: MS2001 6:14 unknown binding Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
