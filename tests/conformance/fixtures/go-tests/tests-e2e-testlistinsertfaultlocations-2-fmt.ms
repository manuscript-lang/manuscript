# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/list_parity_test.go:17 TestListInsertFaultLocations
export fn main() Int:
    let values = [1, 2]
    values.insert(-3, 9)
    return values.length()
