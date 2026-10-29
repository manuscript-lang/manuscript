# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:162 TestFaultSourceLocations
fn divide(value: Int = 1 / "".byte_length()) Int:
    return value

export fn main() Int:
    return divide()
