# conform: tags=control-flow,faults,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=tests/e2e/fault_locations_test.go:141 TestFaultSourceLocations
import panic from "@std/faults.ms"
test "several checks":
    let good = 2 + 3
    if good == 5:
        panic("last check failed")
