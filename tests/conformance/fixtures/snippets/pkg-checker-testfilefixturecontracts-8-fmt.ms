# conform: tags=formatter,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:58 TestFileFixtureContracts
fn make_fixture() State:
    return State(1)
test "test":
    return
