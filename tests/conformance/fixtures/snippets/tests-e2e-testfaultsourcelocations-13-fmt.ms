# conform: tags=formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:118 TestFaultSourceLocations
def crash(key: String, value: Int) -> Bool:
    return 1 / value == 0

export def main() -> Int:
    let value: Map[String, Int] = {"a": 0}
    return value.filter(crash).length()
