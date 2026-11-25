// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"
import File from "@std/io/io.ms"
import Queue from "@std/queues.ms"
interface Read {
    fn get() Int
}
type Val {
    val Int
}
impl Read for Val {
    fn get() Int {
        return self.val
    }
}
// expect-error: MS1000 12:1-12:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
