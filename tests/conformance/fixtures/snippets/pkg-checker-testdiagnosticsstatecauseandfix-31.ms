# conform: tags=closures,diagnostics,modules,stdlib-queues,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/hints_test.go:50 TestDiagnosticsStateCauseAndFix
import PriorityQueue from "@std/queue.ms"

fn f() Int:
    var q = PriorityQueue(
        compare: fn(left: HttpMethod, right: HttpMethod) Int: return 0
    )
    return 0
