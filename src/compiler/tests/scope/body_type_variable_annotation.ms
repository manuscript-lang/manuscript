fn keep[T](value: T) T:
	copy: T := value
	return copy

fn first[T, U](a: T, b: U) T:
	left: T := a
	return left
