# conform: tags=control-flow,diagnostics,interfaces,testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:52 TestFileFixtureContracts
impl TestHooks for State:

fn make_fixture() TestHooks:
    return State(1)

test "test":
    return
