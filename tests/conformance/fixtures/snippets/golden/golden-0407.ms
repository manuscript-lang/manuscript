// conform: tags=diagnostics
// conform: phase=check
impl TestHooks for State:
    fn before_each() Unit:
        self.value = self.value + 1
fn make_fixture() State:
    return State(value: 1)
test "closure captures fixture":
    read := fn() Int: fixture.value
    value: Int := read()
