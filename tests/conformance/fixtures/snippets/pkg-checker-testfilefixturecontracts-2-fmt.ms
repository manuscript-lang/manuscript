# conform: tags=control-flow,formatter,interfaces,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:17 TestFileFixtureContracts
impl TestHooks for State:
fn make_fixture() State:
    return State(value: 1)
test "reads fixture":
    let value: Int = fixture.value
