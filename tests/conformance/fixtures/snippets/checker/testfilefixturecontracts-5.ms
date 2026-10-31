# conform: tags=control-flow,diagnostics,interfaces,testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:40 TestFileFixtureContracts
impl TestHooks for State:

fn make_fixture(value: Int) State:
    return State(value)

test "test":
    return
