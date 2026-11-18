type Box[T: Clonable]:
	value: T

fn Box[T: Clonable].get() T:
	return self.value.clone()

fn Box[T: Clonable].map[B: Clonable](change: fn(T) B) List[B]:
	out: List[B] := []
	return out

fn first[T](items: List[T]) T?:
	return items.get(0)

fn second[T](items: List[T]) T?:
	return items.get(1)

fn main() Void:
	print(first([1]))
