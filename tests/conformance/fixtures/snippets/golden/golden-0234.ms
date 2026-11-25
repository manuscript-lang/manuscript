// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"

fn f(q Queue[Int]) Int {
	q.capacity = 5
	return q.capacity
}
// expect-error: MS2002 3:8-3:13 unknown standard module @std/queues.ms; did you mean '@std/collections/queue.ms'?
// expect-error: MS2001 5:8 unknown type Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
// expect-error: MS3000 6:7 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
