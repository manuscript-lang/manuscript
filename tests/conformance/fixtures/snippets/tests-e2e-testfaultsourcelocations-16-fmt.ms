# conform: tags=faults,formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:136 TestFaultSourceLocations
def deep(l: List[Int], i: Int) -> Int:
    return l.get(i)

export def main() -> Int:
    return deep(l: [1], i: 5)
