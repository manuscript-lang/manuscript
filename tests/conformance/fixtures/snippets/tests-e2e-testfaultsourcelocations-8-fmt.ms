# conform: tags=faults,formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:87 TestFaultSourceLocations
def pick(values: List[Int], index: Int) -> Int:
    return values.get(index)

export def main() -> Int:
    return pick([1, 2, 3], 3)
