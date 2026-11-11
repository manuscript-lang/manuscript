// conform: tags=formatter,lists,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/list_take_drop_test.go:23 TestListTakeDropFaultLocations
export fn main() Int:
    empty: List[Int] := []
    part := empty.METHOD(-7)
    return part.length()
