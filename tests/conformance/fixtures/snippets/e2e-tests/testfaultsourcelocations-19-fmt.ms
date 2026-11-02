# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:153 TestFaultSourceLocations
fn divide(value: Int) Int:
    return 1 / value

fn outer(value: Int) Int:
    return value

export fn main() Int:
    return outer(divide(0))
