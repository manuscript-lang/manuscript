// conform: tags=ownership,optionals,tier-core
// conform: phase=run
// conform: origin=design/proposals/argument-modes-in-signatures.md
type Item {
	name String
	tags List[String]
}

type Bag {
	items List[Item]
}

fn hold Bag.lowest() &Item? {
	if self.items.length() == 0 { return null }

	var best = 0
	for i in 1..self.items.length() {
		if self.items[i].name.compare(
			self.items[best].name
		) < 0 { best = i }
	}
	return self.items[best]
}

fn pick(hold bag Bag) &Item? {
	return bag.lowest()
}

fn main() Void {
	bag := Bag([Item("b", ["x"]), Item("a", ["y"])])
	item := pick(bag)
	if item != null {
		print(item.name)
	}
}
