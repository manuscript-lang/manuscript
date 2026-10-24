# conform: tags=diagnostics,testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:58 TestFileFixtureContracts
def make_fixture() -> State:
    return State(1)

test "test":
    return
