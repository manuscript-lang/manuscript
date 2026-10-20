# conform: tags=control-flow,interfaces,modules,parser,records,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:351 TestFileFixtureCompletion
import TestHooks from "@std/testing.ms"
type State:
    count: Int
fn make_fixture() State:
    return State(0)
impl TestHooks for State:
test "one":
    fixture.|
