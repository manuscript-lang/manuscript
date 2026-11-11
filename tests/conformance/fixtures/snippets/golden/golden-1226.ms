// conform: tags=diagnostics
// conform: phase=check
import TestHooks from "@std/test/test.ms"
type State:
    count: Int
fn make_fixture() State:
    return State(0)
impl TestHooks for State:
test "one":
    fixture.|
