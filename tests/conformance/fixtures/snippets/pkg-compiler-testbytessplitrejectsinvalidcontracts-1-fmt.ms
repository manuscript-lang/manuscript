# conform: tags=formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/bytes_split_test.go:13 TestBytesSplitRejectsInvalidContracts
def wrong(data: Bytes) -> List[Bytes]:
    let split = data.split
    return split(value: Bytes([]))
