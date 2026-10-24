# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/bytes_split_test.go:13 TestBytesSplitRejectsInvalidContracts
def wrong(data: Bytes) -> List[Bytes]:
    let split = data.split
    return split(value: Bytes([]))
