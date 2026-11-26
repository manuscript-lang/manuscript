// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"

fn read(state Queue[Int]) Int {
	return state.length()
}

fn named(state Queue[Int], value Int = read(state)) Int {
	return value
}

fn nested(state Queue[Int]) Void {
	callback := fn(value Int = read(state)) Int {
		return value
	}
}
// expect-error: MS2002 3:8-3:13 unknown standard module @std/queues.ms; did you mean '@std/collections/queue.ms'?
// expect-error: MS2001 5:15 unknown type Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
// expect-error: MS2001 9:16 unknown type Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
// expect-error: MS2001 13:17 unknown type Queue; add: import Queue from "@std/collections/queue.ms"
// expect-fix: 1:1-1:1 "import Queue from \"@std/collections/queue.ms\"\n"
