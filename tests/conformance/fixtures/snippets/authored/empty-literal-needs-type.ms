// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=empty literal types
fn count[T](values List[T]) Int {
	return values.length()
}

fn main() Void {
	annotated List[Int] := []
	print(annotated.length())
	print(count[Int]([]))
	print(count([1]))
	print(count([]))
	unknown := []
	table := {}
	print(unknown.length() + table.length())
}
// expect-error: MS3080 13:17 cannot infer list element type; add an annotation, e.g. xs List[Int] := []
// expect-error: MS3080 14:16 cannot infer list element type; add an annotation, e.g. xs List[Int] := []
// expect-error: MS3080 15:14 cannot infer map key and value types; add an annotation, e.g. m Map[String, Int] := {}
