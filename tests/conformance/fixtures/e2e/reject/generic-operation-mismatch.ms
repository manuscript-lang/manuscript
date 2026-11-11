// conform: tags=testing,tier-core
// conform: phase=check
type Bag:
	items: List[Int]

interface Picker:
	fn mapped[U](transform: fn(Int) U) List[U]

fn Bag.mapped(transform: fn(Int) Int) List[Int]:
	return self.items

fn pick() Picker:
	return Bag([1])

export fn main() Int:
	return 0
