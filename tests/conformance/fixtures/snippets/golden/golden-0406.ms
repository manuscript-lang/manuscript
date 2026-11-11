// conform: tags=diagnostics
// conform: phase=check
impl TestHooks for State:
fn make_fixture() State:
    return State(value: 1)
test "reads fixture":
    value: Int := fixture.value
