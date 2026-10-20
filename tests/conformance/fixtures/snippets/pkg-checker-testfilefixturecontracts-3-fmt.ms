# conform: tags=closures,control-flow,formatter,interfaces,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/test_fixture_test.go:23 TestFileFixtureContracts
impl TestHooks for State:
    fn before_each() Unit:
        self.value = self.value + 1
fn make_fixture() State:
    return State(value: 1)
test "closure captures fixture":
    let read = fn() Int: fixture.value
    let value: Int = read()
