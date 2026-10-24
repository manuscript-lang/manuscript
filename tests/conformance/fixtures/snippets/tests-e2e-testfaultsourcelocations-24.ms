# conform: tags=lists,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:189 TestFaultSourceLocations
def empty() -> List[Int]:
    return []

export def main() -> Int:
    let [value] = empty()
    return value
