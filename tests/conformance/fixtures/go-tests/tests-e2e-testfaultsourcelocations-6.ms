# conform: tags=maps,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:74 TestFaultSourceLocations
fn crash() Int:
    return 1 / 0
export fn main() Int:
    var values = Map[Int, Int]()
    values.add(crash(), 1)
    return values.length()
