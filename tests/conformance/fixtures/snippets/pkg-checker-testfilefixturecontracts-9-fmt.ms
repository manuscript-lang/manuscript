# conform: tags=control-flow,formatter,interfaces,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:63 TestFileFixtureContracts
impl TestHooks for State:
fn make_fixture() State:
    return State(fixture.value)
test "test":
    return
