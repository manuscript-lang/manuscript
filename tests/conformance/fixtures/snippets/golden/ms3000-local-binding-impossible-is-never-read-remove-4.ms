// conform: tags=diagnostics
// conform: phase=check
fn difference(values List[Int]) Int {
	[first, second] := values
	return first - second
}

test "fault" {
	impossible := difference(values: [1])
}
// expect-error: MS3000 9:5 local binding impossible is never read; remove it, use it, or name it with a leading '_' to ignore it
