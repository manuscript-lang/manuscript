// conform: tags=faults,formatter,optional,parser,testing,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/e2e_test.go:67 TestRuntimeFaults
test "fault":
    missing: Int? := none
    _impossible := missing.get()
