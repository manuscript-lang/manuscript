# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/bytes_split_test.go:14 TestBytesSplitLimitFaultLocations
export fn main() Int:
    let data = Bytes([])
    let parts = data.split(Bytes([0]), -7)
    return parts.length()
