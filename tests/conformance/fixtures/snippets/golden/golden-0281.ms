// conform: tags=diagnostics
// conform: phase=check
import PriorityQueue from "@std/queues.ms"
fn f() Int:
    q := PriorityQueue(compare: fn(left: HttpMethod, right: HttpMethod) Int: return 0)
    return 0
