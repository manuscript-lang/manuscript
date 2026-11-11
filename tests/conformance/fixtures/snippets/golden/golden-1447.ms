// conform: tags=diagnostics
// conform: phase=check
fn difference(values: List[Int]) Int:
    [first, second] := values
    return first - second
test "fault":
    impossible := difference(values: [1])
