# conform: tags=control-flow,formatter,generics,interfaces,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:46 TestFileFixtureContracts
impl TestHooks for State:

fn make_fixture[T]() State:
    return State(1)

test "test":
    return
