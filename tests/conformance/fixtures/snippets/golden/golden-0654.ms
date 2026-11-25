// conform: tags=diagnostics
// conform: phase=check
fn use() Set[Int] {
	values Set[Int] := Set()
	return values.add(1)
}
// expect-error: MS3001 5:19 expected Set[Int], found Void (in the return value)
