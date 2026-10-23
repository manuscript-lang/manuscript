# conform: tags=testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/e2e_test.go:70 TestRuntimeFaults
fn divide(value: Int, divisor: Int) Int:
    return value / divisor

test "fault":
    let impossible = divide(value: 3, divisor: 0)
