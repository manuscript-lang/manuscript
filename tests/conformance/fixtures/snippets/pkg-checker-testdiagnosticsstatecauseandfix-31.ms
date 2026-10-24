# conform: tags=closures,diagnostics,modules,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:50 TestDiagnosticsStateCauseAndFix
from "@std/queue.ms" import PriorityQueue

def f() -> Int:
    var q = PriorityQueue(
        compare: lambda (left: HttpMethod, right: HttpMethod) -> Int: return 0
    )
    return 0
