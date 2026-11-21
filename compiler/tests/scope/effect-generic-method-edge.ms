type Box[T]:
	item: T

fn Box[T].get() T:
	return self.item

fn run() Int:
	b := Box(item: 3)
	return b.get()
