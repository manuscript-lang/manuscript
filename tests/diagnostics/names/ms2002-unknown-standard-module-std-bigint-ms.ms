// conform: tags=diagnostics
// conform: phase=check
import (
	from_int from "@std/bigint.ms",
	Bytes, BytesBuilder from "@std/bytes.ms",
	PriorityQueue, Queue from "@std/queues.ms",
)

fn compare(left Int, right Int) Int => left - right
// expect-error: MS2002 4:5-4:13 unknown standard module @std/bigint.ms
// expect-error: MS2002 6:5-6:18 unknown standard module @std/queues.ms; did you mean '@std/collections/queue.ms'?
// expect-error: MS2002 6:20-6:25 unknown standard module @std/queues.ms; did you mean '@std/collections/queue.ms'?
