# conform: tags=formatter,maps,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:74 TestFaultSourceLocations
def crash() -> Int:
    return 1 / "".byte_length()

export def main() -> Int:
    var values = Map[Int, Int]()
    values.add(crash(), 1)
    return values.length()
