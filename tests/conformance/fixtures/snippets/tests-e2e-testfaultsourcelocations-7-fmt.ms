# conform: tags=formatter,maps,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:80 TestFaultSourceLocations
def crash() -> Int:
    return 1 / 0

export def main() -> Int:
    var values = Map[Int, Int]()
    let add = values.add
    add(value: crash(), key: 1)
    return values.length()
