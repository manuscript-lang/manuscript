# conform: tags=closures,control-flow,diagnostics,interfaces,testing,tier-core
# conform: phase=check
# conform: origin=pkg/checker/test_fixture_test.go:23 TestFileFixtureContracts
impl TestHooks for State:
    def before_each() -> Unit:
        self.value = self.value + 1

def make_fixture() -> State:
    return State(value: 1)

test "closure captures fixture":
    let read = lambda () -> Int: fixture.value
    let value: Int = read()
