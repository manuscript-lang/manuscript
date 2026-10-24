# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/bytes_split_test.go:14 TestBytesSplitLimitFaultLocations
export def main() -> Int:
    let data = Bytes([])
    let parts = data.split(Bytes([0]), -7)
    return parts.length()
