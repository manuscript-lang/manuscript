# conform: tags=diagnostics,modules,stdlib-bigint,stdlib-bytes,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=tests/e2e/precondition_diagnostics_test.go:45 TestPreconditionDiagnostics
from "@std/bytes.ms" import Bytes, BytesBuilder
from "@std/queue.ms" import PriorityQueue, Queue
from "@std/math.ms" import from_int

def compare(left: Int, right: Int) -> Int: left - right
