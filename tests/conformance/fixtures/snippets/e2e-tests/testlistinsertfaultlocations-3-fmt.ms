// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/list_parity_test.go:22 TestListInsertFaultLocations
export fn main() Int:
    var values = [1]
    let insert = values.insert
    insert(index: 5, value: 9)
    return 0
