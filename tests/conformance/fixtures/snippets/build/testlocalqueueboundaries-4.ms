// conform: tags=diagnostics,modules,stdlib-cleanup,stdlib-queues,tier-stdlib
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:676 TestLocalQueueBoundaries
import (
	Queue from "@std/collections/queue.ms",
	Closeable from "@std/core.ms",
)

fn invalid() Void { ... }
// expect-exit: 0
