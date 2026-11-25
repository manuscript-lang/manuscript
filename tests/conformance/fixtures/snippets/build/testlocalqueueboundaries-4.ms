// conform: tags=diagnostics,formatter,modules,stdlib-cleanup,stdlib-queues,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:676 TestLocalQueueBoundaries
import (
	Queue from "@std/collections/queue.ms",
	Closeable from "@std/core.ms",
)

fn invalid() Void { ... }
// expect-exit: 0
