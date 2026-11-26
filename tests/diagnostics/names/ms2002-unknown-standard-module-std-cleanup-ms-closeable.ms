// conform: tags=diagnostics
// conform: phase=check
import (
	Closeable from "@std/cleanup.ms",
	Queue from "@std/queues.ms",
)

fn invalid() Void { ... }
// expect-error: MS2002 4:5-4:14 unknown standard module @std/cleanup.ms; Closeable is exported by another standard module, so write: import Closeable from "@std/core.ms"
// expect-error: MS2002 5:5-5:10 unknown standard module @std/queues.ms; did you mean '@std/collections/queue.ms'?
