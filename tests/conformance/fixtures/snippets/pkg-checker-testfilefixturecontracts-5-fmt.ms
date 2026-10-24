# conform: tags=control-flow,formatter,interfaces,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:40 TestFileFixtureContracts
impl TestHooks for State:

def make_fixture(value: Int) -> State:
    return State(value)

test "test":
    return
