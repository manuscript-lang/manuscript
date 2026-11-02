# conform: tags=faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:104 TestFaultSourceLocations

fn crash(value: Int) Int:
    return 1 / value

export fn main() Int:
    let value: Int!Error = ok(0)
    return value.map(crash).get()
