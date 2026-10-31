# conform: tags=functions,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:147 TestFaultSourceLocations
fn zero() Int:
    return 0

export fn main() Int:
    return (1 / zero())
