// conform: tags=diagnostics
// conform: phase=check
fn use() Int {
	nested List[List[Int]] := [[], [1]]
	empty Map[String, Int] := {}
	return Map[String, Int]().add("a", nested[1][0]).get("a").get()
}
// expect-error: MS2001 6:54 unknown or ambiguous member get on Void; this type has no fields or operations
