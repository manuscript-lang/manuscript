# conform: tags=maps,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:80 TestFaultSourceLocations
fn crash() Int:
    return 1 / 0

export fn main() Int:
    var values = Map[Int, Int]()
    let add = values.add
    add(value: crash(), key: 1)
    return values.length()
