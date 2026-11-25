// conform: tags=diagnostics
// conform: phase=check
import PriorityQueue from "@std/queues.ms"

fn f() Int {
	q := PriorityQueue(compare: fn(left HttpMethod, right HttpMethod) Int => return 0)
	return 0
}
// expect-error: MS2002 3:8-3:21 unknown standard module @std/queues.ms; did you mean '@std/collections/queue.ms'?
// expect-error: MS2001 6:10 unknown binding PriorityQueue; add: import PriorityQueue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import PriorityQueue from \"@std/collections/queue.ms\"\n"
// expect-error: MS2001 6:41 unknown type HttpMethod; add: import HttpMethod from "@std/net/http.ms"
// expect-fix: 1:1-1:1 "import HttpMethod from \"@std/net/http.ms\"\n"
// expect-error: MS2001 6:59 unknown type HttpMethod; add: import HttpMethod from "@std/net/http.ms"
// expect-fix: 1:1-1:1 "import HttpMethod from \"@std/net/http.ms\"\n"
