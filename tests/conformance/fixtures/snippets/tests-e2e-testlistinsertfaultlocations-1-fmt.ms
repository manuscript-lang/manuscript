# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/list_parity_test.go:12 TestListInsertFaultLocations
export def main() -> Int:
    var values = [1, 2]
    values.insert(3, 9)
    return values.length()
