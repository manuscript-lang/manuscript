// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/list_parity_test.go:22 TestListInsertFaultLocations
fn main() Unit:
    var values = [1]
    insert := values.insert
    insert(index: 5, value: 9)
