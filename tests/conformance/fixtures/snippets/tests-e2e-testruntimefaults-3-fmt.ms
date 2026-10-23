# conform: tags=formatter,parser,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:69 TestRuntimeFaults
fn sum(value: Int) Int:
    return value + 1

test "fault":
    let impossible = sum(value: 9223372036854775807)
