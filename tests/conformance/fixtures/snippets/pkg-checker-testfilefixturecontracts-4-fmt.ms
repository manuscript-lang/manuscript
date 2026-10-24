# conform: tags=control-flow,formatter,interfaces,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:32 TestFileFixtureContracts
impl TestHooks for State:
    def before_each(value: Int) -> Unit:
        return

def make_fixture() -> State:
    return State(value: 1)

test "test":
    return
