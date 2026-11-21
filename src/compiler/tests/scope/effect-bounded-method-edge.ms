type Pair[T]:
	item: T

fn Pair[T: Equal].same(other: Pair[T]) Bool:
	return true

fn run() Bool:
	a := Pair(item: 1)
	return a.same(a)
