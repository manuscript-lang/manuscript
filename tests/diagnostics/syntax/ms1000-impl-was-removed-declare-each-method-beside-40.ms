// conform: tags=diagnostics
// conform: phase=check
impl TestHooks for State {
    fn before_each() Void {
        self.value = self.value + 1
    }
}
fn make_fixture() State {
    return State(value: 1)
}
test "closure captures fixture" {
    read := fn() Int => fixture.value
    value: Int := read()
}
// expect-error: MS1000 3:1-3:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 13:10-13:11 remove the ':' between 'value' and its type; write value Type
// expect-fix: 13:10-13:11 ""
