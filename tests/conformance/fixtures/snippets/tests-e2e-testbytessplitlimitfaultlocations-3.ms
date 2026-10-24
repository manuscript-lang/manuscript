# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=tests/e2e/bytes_split_test.go:25 TestBytesSplitLimitFaultLocations
export def main() -> Int:
    let cap: Optional[Int] = some(-7)
    let parts = Bytes([1]).split(Bytes([]), cap)
    return parts.length()
