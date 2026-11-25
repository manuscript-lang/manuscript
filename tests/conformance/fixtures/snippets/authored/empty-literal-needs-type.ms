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
