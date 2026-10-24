# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:167 TestFaultSourceLocations
export def main() -> Int:
    let crash = lambda () -> Int:
        return 1 / 0
    return crash()
