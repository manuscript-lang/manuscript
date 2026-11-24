// conform: tags=diagnostics
// conform: phase=check
fn first() Void {
	result Result[Int, TextError] := fail("empty")
}
