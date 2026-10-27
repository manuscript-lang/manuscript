# conform: tags=testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/e2e_test.go:69 TestRuntimeFaults
def sum(value: Int) -> Int:
    return value + 1

test "fault":
    let _impossible = sum(value: 9223372036854775807)
