// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/list_take_drop_test.go:13 TestListTakeDropFaultLocations
export fn main() Int:
    values := [1, 2]
    part := values.METHOD(-7)
    return part.length()
