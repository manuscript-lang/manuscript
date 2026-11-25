// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
type Override {
    received Bool
}
impl FileSystem for Override {
}
// expect-error: MS1000 7:1-7:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
