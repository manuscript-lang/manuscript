# conform: tags=aliasing,lists,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/e2e_test.go:71 TestRuntimeFaults
fn difference(values: List[Int]) Int:
    let [first, second] = values
    return first - second
test "fault":
    let impossible = difference(values: [1])
