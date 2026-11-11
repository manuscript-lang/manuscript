// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"
fn f(q: Queue[Int]) Int:
    q.capacity = 5
    return q.capacity
