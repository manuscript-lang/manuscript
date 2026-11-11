// conform: tags=diagnostics
// conform: phase=check
interface TestHooks:
    fn after_all() Unit
type State:
    value: Int
impl TestHooks for State:
    fn after_all() Unit:
        return
fn make_fixture() State:
    return State(1)
test "test":
    return
