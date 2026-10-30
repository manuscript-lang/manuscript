# conform: tags=faults,optional,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:130 TestFaultSourceLocations
fn crash(value: Int) Int?:
    return some(1 / value)

export fn main() Int:
    let value: Int? = some(0)
    return value.and_then(crash).get()
