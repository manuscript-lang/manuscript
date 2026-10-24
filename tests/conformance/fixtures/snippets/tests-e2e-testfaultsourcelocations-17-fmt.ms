# conform: tags=control-flow,faults,formatter,modules,parser,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:141 TestFaultSourceLocations
from "@std/core.ms" import panic

test "several checks":
    let good = 2 + 3
    if good == 5:
        panic("last check failed")
