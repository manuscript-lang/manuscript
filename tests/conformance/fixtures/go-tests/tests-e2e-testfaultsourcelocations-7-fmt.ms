# conform: tags=formatter,maps,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:80 TestFaultSourceLocations
fn crash() Int:
    return 1 / 0
export fn main() Int:
    let values = Map[Int, Int]()
    let add = values.add
    return add(value: crash(), key: 1).length()
