// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"
fn read(queue Queue[Int]) Void {
    queue.|
}
// expect-error: MS1000 5:11-5:12 expected a name, found '|'
