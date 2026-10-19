# conform: tags=functions,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:153 TestFaultSourceLocations
fn divide(value: Int) Int:
    return 1 / value
fn outer(value: Int) Int:
    return value
export fn main() Int:
    return outer(
        divide(0)
    )
