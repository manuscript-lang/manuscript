# conform: tags=diagnostics,modules,stdlib-cleanup,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:676 TestLocalQueueBoundaries
import Queue from "@std/queues.ms"
import Closeable from "@std/cleanup.ms"
fn invalid() Unit:
    
