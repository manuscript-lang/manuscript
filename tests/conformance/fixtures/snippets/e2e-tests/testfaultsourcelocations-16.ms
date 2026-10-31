# conform: tags=faults,lists,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:136 TestFaultSourceLocations
fn deep(l: List[Int], i: Int) Int:
    return l.get(i)

export fn main() Int:
    return deep(l: [1], i: 5)
