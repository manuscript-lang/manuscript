# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/bytes_split_test.go:19 TestBytesSplitLimitFaultLocations
export fn main() Int:
    let data = Bytes([1, 0, 2])
    let split = data.split
    let parts = split(max_parts: -7, separator: Bytes([0]))
    return parts.length()
