// conform: tags=diagnostics
// conform: phase=check
import Closeable from "@std/cleanup.ms"
type Resource {
    visits List[Int]
}
impl Closeable for Resource {
    fn close() Void {
        self.visits.append(1)
    }
}
// expect-error: MS1000 7:1-7:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
