# conform: tags=formatter,modules,parser,stdlib-cleanup,stdlib-queues,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:676 TestLocalQueueBoundaries
import Queue from "@std/queue.ms"
import Closeable from "@std/core.ms"

fn invalid() Unit: ...
