// conform: tags=diagnostics
// conform: phase=check
impl TestHooks for State {
}
fn make_fixture() TestHooks {
    return State(1)
}
test "test" {
    return
}
// expect-error: MS1000 3:1-3:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
