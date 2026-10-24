# conform: tags=diagnostics,modules,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:31 TestDiagnosticFixes
from "@std/queue.ms" import Queue

def f(q: Queue[Int]) -> Int:
    q.capacity = 5
    return q.capacity
