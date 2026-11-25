// conform: tags=diagnostics
// conform: phase=check
type Selection {
	values Set[Int]
}

fn keep[T Hashable](values Set[T], value T) Set[T] => values.add(value)

fn use() Set[Int] {
	values Set[Int] := Set[Int]()
	nested List[Set[Int]] := [values]
	return keep(nested[0], 1)
}
// expect-error: MS3001 7:62 expected Set[T], found Void (in the return value)
