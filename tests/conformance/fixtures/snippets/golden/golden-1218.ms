// conform: tags=diagnostics
// conform: phase=check
import Queue from "@std/queues.ms"
fn text(value Queue[Int]) String {
    return value.|
}
// expect-error: MS1000 5:18-5:19 expected a name, found '|'
