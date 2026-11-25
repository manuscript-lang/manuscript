// conform: tags=diagnostics
// conform: phase=check
import expect_true, fail from "@std/test/test.ms"

interface Read {
    fn get() Int
}
type Box[T] {
    value T
}
impl Read for Box[T] {
    fn get() Int {
        return 3
    }
}
test "encoded nominal identity" {
    box := Box(value: 1)
    view := Read(value: box)
    if not (view.get() == 3) {
        return fail("check failed")
    }
}
// expect-error: MS1000 11:1-11:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
