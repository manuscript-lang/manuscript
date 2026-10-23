# conform: tags=control-flow,diagnostics,interfaces,testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:63 TestFileFixtureContracts
impl TestHooks for State:

fn make_fixture() State:
    return State(fixture.value)

test "test":
    return
