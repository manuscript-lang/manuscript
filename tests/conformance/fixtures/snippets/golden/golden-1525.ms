// conform: tags=diagnostics
// conform: phase=check
import (
	from_int from "@std/bigint.ms",
	Bytes, BytesBuilder from "@std/bytes.ms",
	PriorityQueue, Queue from "@std/queues.ms",
)

fn compare(left Int, right Int) Int => left - right
