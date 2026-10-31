# conform: tags=lists,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:189 TestFaultSourceLocations
fn empty() List[Int]:
    return []

export fn main() Int:
    let [value] = empty()
    return value
