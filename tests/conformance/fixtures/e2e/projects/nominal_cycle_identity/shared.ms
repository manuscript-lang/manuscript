import Door from "./inner.ms"

type Pair[T] {
	first T
	second T
}

export fn exercise_shared(
	first String,
	second String,
	third String,
	fourth String,
) Void {
	held := Pair(
		Pair(Door(first.clone().clone()), Door(second.clone())),
		Pair(Door(third.clone()), Door(fourth.clone())),
	)
	_borrowed_path := held.first.first.path
}
