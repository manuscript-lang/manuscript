# conform: tags=control-flow,diagnostics,generics,interfaces,testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:46 TestFileFixtureContracts
impl TestHooks for State:

def make_fixture[T]() -> State:
    return State(1)

test "test":
    return
