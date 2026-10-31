# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/bytes_split_test.go:25 TestBytesSplitLimitFaultLocations
export fn main() Int:
    let cap: Int? = -7
    let parts = Bytes([1]).split(Bytes([]), cap)
    return parts.length()
