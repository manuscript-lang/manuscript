// conform: tags=formatter,lists,testing,tier-core
// conform: phase=test,parse
// conform: origin=tests/e2e/e2e_test.go:71 TestRuntimeFaults
fn difference(values List[Int]) Int {
	[first, second] := values
	return first - second
}

test "fault" {
	_impossible := difference(values: [1])
}
