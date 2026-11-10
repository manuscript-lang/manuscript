// conform: tags=diagnostics,lists,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/bytes_split_test.go:13 TestBytesSplitRejectsInvalidContracts
fn wrong(data: Bytes) List[Bytes]:
    split := data.split
    return split(value: Bytes([]))
