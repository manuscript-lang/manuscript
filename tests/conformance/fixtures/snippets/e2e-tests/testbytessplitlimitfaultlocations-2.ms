// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/bytes_split_test.go:19 TestBytesSplitLimitFaultLocations
export fn main() Int:
    data := Bytes([1, 0, 2])
    split := data.split
    parts := split(max_parts: -7, separator: Bytes([0]))
    return parts.length()
