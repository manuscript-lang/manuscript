# conform: tags=sets,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:124 TestFaultSourceLocations
def crash(value: Int) -> Int:
    return 1 / value

export def main() -> Int:
    var value = Set[Int]()
    value.add(0)
    return value.map(crash).length()
