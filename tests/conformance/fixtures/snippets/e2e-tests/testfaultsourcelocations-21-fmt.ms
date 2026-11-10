// conform: tags=closures,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/fault_locations_test.go:167 TestFaultSourceLocations
export fn main() Int:
    crash := fn() Int:
        return 1 / "".byte_length()
    return crash()
