// conform: tags=faults,optional,testing,tier-core
// conform: phase=test
// conform: origin=tests/e2e/e2e_test.go:67 TestRuntimeFaults
test "fault":
    missing: Int? := none
    _impossible := missing.get()
