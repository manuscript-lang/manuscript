# conform: tags=faults,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:92 TestFaultSourceLocations

fn deep(value: Int!Error) Int:
    return value.get()

export fn main() Int:
    return deep(error(Error("expected failure")))
