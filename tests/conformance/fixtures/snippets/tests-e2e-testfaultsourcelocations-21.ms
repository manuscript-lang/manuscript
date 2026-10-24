# conform: tags=closures,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:167 TestFaultSourceLocations
export def main() -> Int:
    let crash = lambda () -> Int:
        return 1 / 0
    return crash()
