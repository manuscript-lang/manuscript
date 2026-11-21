type Box[T]:
	value: T

fn Box[T].get() T:
	held: T := self.value
	return held

fn Box[T].swap_with[U](other: U) U:
	kept: U := other
	return kept
