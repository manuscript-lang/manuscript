# conform: tags=closures,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:167 TestFaultSourceLocations
export fn main() Int:
    let crash = fn() Int:
        return 1 / "".byte_length()
    return crash()
