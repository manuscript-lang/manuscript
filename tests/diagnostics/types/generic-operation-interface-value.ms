// conform: tags=testing,tier-core
// conform: phase=check
type Bag {
	items List[Int]
}

interface Picker {
	fn mapped[U](transform fn(Int) U) List[U]
}

fn Bag.mapped[U](transform fn(Int) U) List[U] {
	var out List[U] = []
	for x in self.items {
		out.append(transform(x))
	}
	return out
}

export fn main() Int {
	picker Picker := Bag(items: [1])
	return 0
}
// expect-error: MS3001 20:22 expected Picker, found Bag (in the initializer of 'picker'); Picker declares an operation with type parameters of its own, so it bounds a type parameter (`fn f[T: Picker](x T)`) but cannot type a value
