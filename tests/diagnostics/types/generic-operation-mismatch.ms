// conform: tags=testing,tier-core
// conform: phase=check
type Bag {
	items List[Int]
}

interface Picker {
	fn mapped[U](transform fn(Int) U) List[U]
}

fn Bag.mapped(transform fn(Int) Int) List[Int] {
	return self.items
}

fn pick() Picker {
	return Bag([1])
}

export fn main() Int {
	return 0
}
// expect-error: MS3001 16:12 expected Picker, found Bag (in the return value); Picker declares an operation with type parameters of its own, so it bounds a type parameter (`fn f[T Picker](x T)`) but cannot type a value
