# conform: tags=control-flow,diagnostics,interfaces,testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:32 TestFileFixtureContracts
impl TestHooks for State:
    def before_each(value: Int) -> Unit:
        return

def make_fixture() -> State:
    return State(value: 1)

test "test":
    return
