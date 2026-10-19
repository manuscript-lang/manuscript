# conform: tags=control-flow,formatter,interfaces,parser,records,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:72 TestFileFixtureContracts
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
