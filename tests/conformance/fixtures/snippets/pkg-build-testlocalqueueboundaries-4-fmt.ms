# conform: tags=formatter,modules,parser,stdlib-cleanup,stdlib-queues,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:676 TestLocalQueueBoundaries
from "@std/queue.ms" import Queue
from "@std/core.ms" import Closeable

def invalid() -> Unit: ...
