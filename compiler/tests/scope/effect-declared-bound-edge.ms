type Tag:
	id: Int

fn Tag.equals(other: Tag) Bool:
	return self.id == other.id

type Pair[T]:
	item: T

fn Pair[T: Equal].same(other: Pair[T]) Bool:
	return true

fn run() Bool:
	a := Pair(item: Tag(id: 1))
	return a.same(a)
