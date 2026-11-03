# conform: tags=modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:111 TestFaultSourceLocations

fn crash(cause: Error) Int:
    return 1 / "".byte_length()

export fn main() Int:
    let value: Int!Error = error(Error("expected failure"))
    return value.get_or_else(crash)
