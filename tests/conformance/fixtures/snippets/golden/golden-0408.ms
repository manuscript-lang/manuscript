// conform: tags=diagnostics
// conform: phase=check
impl TestHooks for State {
    fn before_each(value: Int) Void {
        return
    }
}
fn make_fixture() State {
    return State(value: 1)
}
test "test" {
    return
}
