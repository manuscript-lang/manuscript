// conform: tags=formatter,lists,parser,testing,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/e2e_test.go:71 TestRuntimeFaults
fn difference(values: List[Int]) Int:
    [first, second] := values
    return first - second

test "fault":
    _impossible := difference(values: [1])
