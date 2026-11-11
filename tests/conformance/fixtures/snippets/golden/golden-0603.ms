// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"
import File from "@std/io/io.ms"
import Queue from "@std/queues.ms"
interface Read:
    fn get() Int
type Val:
    val: Int
impl Read for Val:
    fn get() Int:
        return self.val
