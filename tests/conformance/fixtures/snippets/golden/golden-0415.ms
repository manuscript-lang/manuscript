// conform: tags=diagnostics
// conform: phase=check
interface TestHooks {
    fn after_all() Void
}
type State {
    value Int
}
impl TestHooks for State {
    fn after_all() Void {
        return
    }
}
fn make_fixture() State {
    return State(1)
}
test "test" {
    return
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
