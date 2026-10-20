# conform: tags=sets,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:124 TestFaultSourceLocations
fn crash(value: Int) Int:
    return 1 / value
export fn main() Int:
    var value = Set[Int]()
    value.add(0)
    return value.map(crash).length()
