# conform: tags=faults,optional,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:130 TestFaultSourceLocations
def crash(value: Int) -> Optional[Int]:
    return some(1 / value)

export def main() -> Int:
    let value: Optional[Int] = some(0)
    return value.and_then(crash).get()
