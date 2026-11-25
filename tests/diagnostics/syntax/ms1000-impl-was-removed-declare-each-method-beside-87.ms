// conform: tags=diagnostics
// conform: phase=check
import TestHooks from "@std/test/test.ms"
type State {
    count Int
}
fn make_fixture() State {
    return State(0)
}
impl TestHooks for State {
}
test "one" {
    fixture.|
}
// expect-error: MS1000 10:1-10:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 13:13-13:14 expected a name, found '|'
