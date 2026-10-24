# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/list_parity_test.go:22 TestListInsertFaultLocations
export def main() -> Int:
    let insert = [1].insert
    insert(index: 5, value: 9)
    return 0
