// conform: tags=diagnostics
// conform: phase=check
import Closeable from "@std/cleanup.ms"
impl Closeable for Box[T] {
    fn close() Void {
        return
    }
}
export fn loaded() Int {
    return 1
}
// expect-error: MS1000 4:1-4:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
