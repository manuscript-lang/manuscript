# conform: tags=control-flow,formatter,interfaces,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:52 TestFileFixtureContracts
impl TestHooks for State:

def make_fixture() -> TestHooks:
    return State(1)

test "test":
    return
