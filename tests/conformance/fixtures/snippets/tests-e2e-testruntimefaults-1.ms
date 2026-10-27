# conform: tags=faults,optional,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/e2e_test.go:67 TestRuntimeFaults
test "fault":
    let missing: Optional[Int] = none
    let _impossible = missing.get()
